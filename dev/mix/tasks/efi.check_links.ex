defmodule Mix.Tasks.Efi.CheckLinks do
  @shortdoc "Confere se os links da documentação apontam para seções que existem na doc da Efí"

  @moduledoc """
  Baixa cada página de `dev.efipay.com.br` citada nos `@moduledoc` e `@doc` da biblioteca e
  confere se a âncora de cada link existe nela.

      mix efi.check_links

  A Efí renomeia seções sem aviso. Esta tarefa roda no CI, num job à parte, para o link quebrado
  aparecer antes de publicar, e não na mão de quem usa a biblioteca.
  """

  use Mix.Task

  alias Efi.Dev.Documentation

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    {:ok, _apps} = Application.ensure_all_started(:req)

    links =
      for {source, text} <- Documentation.all_docs(),
          url <- Documentation.links(text),
          do: {source, URI.parse(url)}

    broken =
      links
      |> Enum.group_by(fn {_source, uri} -> %{uri | fragment: nil} end)
      |> Enum.flat_map(&broken_links_on_page/1)

    pages = links |> Enum.map(fn {_source, uri} -> uri.path end) |> Enum.uniq() |> length()
    Mix.shell().info("#{length(links)} links em #{pages} páginas da Efí.")

    case broken do
      [] ->
        Mix.shell().info("Todos apontam para uma seção que existe.")

      broken ->
        Enum.each(broken, fn {source, uri, problem} ->
          Mix.shell().error("#{inspect(source)}: #{URI.to_string(uri)} (#{problem})")
        end)

        Mix.raise("#{length(broken)} links quebrados")
    end
  end

  defp broken_links_on_page({page, links}) do
    case Req.get(URI.to_string(page), retry: :transient, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: html}} ->
        anchors = html |> anchors() |> MapSet.new()

        for {source, uri} <- links,
            uri.fragment,
            not MapSet.member?(anchors, URI.decode(uri.fragment)),
            do: {source, uri, "seção não encontrada"}

      {:ok, %Req.Response{status: status}} ->
        for {source, uri} <- links, do: {source, uri, "página respondeu #{status}"}

      {:error, exception} ->
        for {source, uri} <- links, do: {source, uri, Exception.message(exception)}
    end
  end

  defp anchors(html) do
    for [_attribute, id] <- Regex.scan(~r/id="([^"]+)"/, html), do: decode_entities(id)
  end

  defp decode_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#x27;", "'")
  end
end
