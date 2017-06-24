defmodule Earmark.HtmlRenderer do

  alias  Earmark.Block
  alias  Earmark.Context
  alias  Earmark.Options
  import Earmark.Inline,  only: [ convert: 3 ]
  import Earmark.Helpers, only: [ escape: 2 ]
  import Earmark.Helpers.HtmlHelpers
  import Earmark.Message, only: [ add_messages: 2 ]

  def render(blocks, context=%Context{options: %Options{mapper: mapper}}) do
    {contexts, html} =
      mapper.(blocks, &(render_block(&1, context))) |> Enum.unzip()

    errors = contexts
      |> Enum.flat_map(&(&1.options.messages))
    context1 = add_messages(context, errors) 
    {context1, html |> IO.iodata_to_binary()}
  end

  #############
  # Paragraph #
  #############
  defp render_block(%Block.Para{lnb: lnb, lines: lines, attrs: attrs}, context) do
    lines = convert(lines, lnb, context)
    add_attrs!(context, "<p>#{lines.value}</p>\n", attrs, [], lnb)
  end

  ########
  # Html #
  ########
  defp render_block(%Block.Html{html: html}, context) do
    {context, Enum.intersperse(html, ?\n)}
  end

  defp render_block(%Block.HtmlOther{html: html}, context) do
    {context, Enum.intersperse(html, ?\n)}
  end

  #########
  # Ruler #
  #########
  defp render_block(%Block.Ruler{lnb: lnb, type: "-", attrs: attrs}, context) do
    add_attrs!(context, "<hr/>\n", attrs, [{"class", ["thin"]}], lnb)
  end

  defp render_block(%Block.Ruler{lnb: lnb, type: "_", attrs: attrs}, context) do
    add_attrs!(context, "<hr/>\n", attrs, [{"class", ["medium"]}], lnb)
  end

  defp render_block(%Block.Ruler{lnb: lnb, type: "*", attrs: attrs}, context) do
    add_attrs!(context, "<hr/>\n", attrs, [{"class", ["thick"]}], lnb)
  end

  ###########
  # Heading #
  ###########
  defp render_block(%Block.Heading{lnb: lnb, level: level, content: content, attrs: attrs}, context) do
    converted = convert(content, lnb, context)
    html = "<h#{level}>#{converted.value}</h#{level}>\n"
    add_attrs!(converted, html, attrs, [], lnb)
  end

  ##############
  # Blockquote #
  ##############

  defp render_block(%Block.BlockQuote{lnb: lnb, blocks: blocks, attrs: attrs}, context) do
    {context1, body} = render(blocks, context)
    html = "<blockquote>#{body}</blockquote>\n"
    add_attrs!(context1, html, attrs, [], lnb)
  end

  #########
  # Table #
  #########

  defp render_block(%Block.Table{lnb: lnb, header: header, rows: rows, alignments: aligns, attrs: attrs}, context) do
    cols = for _align <- aligns, do: "<col>\n"
    {context1, html} = add_attrs!(context, "<table>\n", attrs, [], lnb)
    html = [ html , "<colgroup>\n", cols, "</colgroup>\n" ]

    context2 = if header do
      ctx = add_table_rows(context1, [header], "th", aligns, lnb)
      %{ctx | value: [ html, "<thead>\n", ctx.value, "</thead>\n" ] }
    else
      %{context1 | value: html}
    end

    context3 =  add_table_rows(context2, rows, "td", aligns, lnb)
    {context3, [context3.value, "</table>\n" ]}
  end

  ########
  # Code #
  ########

  defp render_block(%Block.Code{lnb: lnb, language: language, attrs: attrs} = block, context = %Context{options: options}) do
    class = if language, do: ~s{ class="#{code_classes( language, options.code_class_prefix)}"}, else: ""
    tag = ~s[<pre><code#{class}>]
    lines = options.render_code.(block)
    html = ~s[#{tag}#{lines}</code></pre>\n]
    add_attrs!(context, html, attrs, [], lnb)
  end

  #########
  # Lists #
  #########

  defp render_block(%Block.List{lnb: lnb, type: type, blocks: items, attrs: attrs, start: start}, context) do
    {context1, content} = render(items, context)
    html = "<#{type}#{start}>\n#{content}</#{type}>\n"
    add_attrs!(context1, html, attrs, [], lnb)
  end

  # format a single paragraph list item, and remove the para tags
  defp render_block(%Block.ListItem{lnb: lnb, blocks: blocks, spaced: false, attrs: attrs}, context)
  when length(blocks) == 1 do
    {context1, content} = render(blocks, context)
    content = Regex.replace(~r{</?p>}, content, "")
    html = "<li>#{content}</li>\n"
    add_attrs!(context1, html, attrs, [], lnb)
  end

  # format a spaced list item
  defp render_block(%Block.ListItem{lnb: lnb, blocks: blocks, attrs: attrs}, context) do
    {context1, content} = render(blocks, context)
    html = "<li>#{content}</li>\n"
    add_attrs!(context1, html, attrs, [], lnb)
  end

  ##################
  # Footnote Block #
  ##################

  defp render_block(%Block.FnList{blocks: footnotes}, context) do
    items = Enum.map(footnotes, fn(note) ->
      blocks = append_footnote_link(note)
      %Block.ListItem{attrs: "#fn:#{note.number}", type: :ol, blocks: blocks}
    end)
    {context1, html} = render_block(%Block.List{type: :ol, blocks: items}, context)
    {context1, Enum.join([~s[<div class="footnotes">], "<hr>", html, "</div>"], "\n")}
  end

  #######################################
  # Isolated IALs are rendered as paras #
  #######################################

  defp render_block(%Block.Ial{verbatim: verbatim}, context) do
    {context, "<p>{:#{verbatim}}</p>\n"}
  end

  ####################
  # IDDef is ignored #
  ####################

  defp render_block(%Block.IdDef{}, context), do: {context, ""}

  ###########
  # Plugins #
  ###########

  defp render_block(%Block.Plugin{lines: lines, handler: handler}, context) do
    case handler.as_html(lines) do
      html when is_list(html) -> {context, html}
      {html, errors}          -> {add_messages(context, errors), html}
      html                    -> {context, [html]}
    end
  end

  #####################################
  # And here are the inline renderers #
  #####################################

  def br,                  do: "<br/>"
  def codespan(text),      do: ~s[<code class="inline">#{text}</code>]
  def em(text),            do: "<em>#{text}</em>"
  def strong(text),        do: "<strong>#{text}</strong>"
  def strikethrough(text), do: "<del>#{text}</del>"

  def link(url, text),        do: ~s[<a href="#{url}">#{text}</a>]
  def link(url, text, nil),   do: ~s[<a href="#{url}">#{text}</a>]
  def link(url, text, title), do: ~s[<a href="#{url}" title="#{title}">#{text}</a>]

  def image(path, alt, nil) do
    ~s[<img src="#{path}" alt="#{alt}"/>]
  end

  def image(path, alt, title) do
    ~s[<img src="#{path}" alt="#{alt}" title="#{title}"/>]
  end

  def footnote_link(ref, backref, number), do: ~s[<a href="##{ref}" id="#{backref}" class="footnote" title="see footnote">#{number}</a>]

  # Table rows
  defp add_table_rows(context, rows, tag, aligns, lnb) do
    numbered_rows = rows
      |> Enum.zip(Stream.iterate(lnb, &(&1 + 1)))
    # for {row, lnb1} <- numbered_rows, do: "<tr>\n#{add_tds(context, row, tag, aligns, lnb1)}\n</tr>\n"
    numbered_rows
      |> Enum.reduce(context, fn {row, lnb}, ctxt ->
        inner_context = add_tds(ctxt, row, tag, aligns, lnb)
        %{inner_context | value:  "<tr>\n#{inner_context.value}\n</tr>\n"}
      end)
  end

  defp add_tds(context, row, tag, aligns, lnb) do
    %{context | value: (Enum.reduce(1..length(row), {[], row}, add_td_fn(context, row, tag, aligns, lnb))
    |> elem(0)
    |> Enum.reverse ) }
  end

  defp add_td_fn(context, row, tag, aligns, lnb) do 
    fn n, {acc, _row} ->
      style = cond do
        align = Enum.at(aligns, n - 1) ->
          " style=\"text-align: #{align}\""
        true ->
          ""
      end
      col = Enum.at(row, n - 1)
      converted = convert(col, lnb,  context)
      {["<#{tag}#{style}>#{converted.value}</#{tag}>" | acc], row}
    end
  end


  ###############################
  # Append Footnote Return Link #
  ###############################

  def append_footnote_link(note=%Block.FnDef{}) do
    fnlink = ~s[<a href="#fnref:#{note.number}" title="return to article" class="reversefootnote">&#x21A9;</a>]
    [ last_block | blocks ] = Enum.reverse(note.blocks)
    last_block = append_footnote_link(last_block, fnlink)
    Enum.reverse([last_block | blocks])
    |> List.flatten
  end

  def append_footnote_link(block=%Block.Para{lines: lines}, fnlink) do
    [ last_line | lines ] = Enum.reverse(lines)
    last_line = "#{last_line}&nbsp;#{fnlink}"
    [put_in(block.lines, Enum.reverse([last_line | lines]))]
  end

  def append_footnote_link(block, fnlink) do
    [block, %Block.Para{lines: fnlink}]
  end

  def render_code(%Block.Code{lines: lines}) do
    lines |> Enum.join("\n") |> escape(true)
  end

  defp code_classes(language, prefix) do
   ["" | String.split( prefix || "" )]
     |> Enum.map( fn pfx -> "#{pfx}#{language}" end )
     |> Enum.join(" ")
  end

end
