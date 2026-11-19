defmodule Efi.Test.MtlsServer do
  @moduledoc false

  # Servidor HTTPS mínimo que, como a Efí, recusa a conexão sem o certificado da aplicação.
  # Responde a qualquer pedido com JSON e conta ao processo do teste a linha do pedido e o
  # certificado que o cliente apresentou.

  @token ~s({"access_token":"token-mtls","token_type":"Bearer","expires_in":3600})

  def start!(directory, test_process) do
    {:ok, listen_socket} =
      :ssl.listen(0,
        certfile: file(directory, "server.pem"),
        keyfile: file(directory, "server.key"),
        cacertfile: file(directory, "ca.pem"),
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        active: false,
        mode: :binary,
        reuseaddr: true
      )

    {:ok, {_address, port}} = :ssl.sockname(listen_socket)
    spawn_link(fn -> accept_loop(listen_socket, test_process) end)
    port
  end

  defp accept_loop(listen_socket, test_process) do
    {:ok, socket} = :ssl.transport_accept(listen_socket)

    spawn(fn ->
      with {:ok, socket} <- :ssl.handshake(socket, 5_000) do
        serve(socket, test_process, "")
      end
    end)

    accept_loop(listen_socket, test_process)
  end

  defp serve(socket, test_process, buffer) do
    case read_request(socket, buffer) do
      {:ok, request_line, rest} ->
        {:ok, peer_certificate} = :ssl.peercert(socket)
        send(test_process, {:mtls_request, request_line, peer_certificate})
        :ssl.send(socket, response(request_line))
        serve(socket, test_process, rest)

      {:error, _closed} ->
        :ssl.close(socket)
    end
  end

  defp response(request_line) do
    body = if request_line =~ "/oauth/token", do: @token, else: ~s({"txid":"abc"})

    "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n" <>
      "content-length: #{byte_size(body)}\r\n\r\n" <> body
  end

  defp read_request(socket, buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [head, rest] ->
        [request_line | headers] = String.split(head, "\r\n")
        read_body(socket, request_line, rest, content_length(headers))

      [_incomplete] ->
        with {:ok, data} <- :ssl.recv(socket, 0, 5_000) do
          read_request(socket, buffer <> data)
        end
    end
  end

  defp read_body(_socket, request_line, buffer, length) when byte_size(buffer) >= length do
    <<_body::binary-size(length), rest::binary>> = buffer
    {:ok, request_line, rest}
  end

  defp read_body(socket, request_line, buffer, length) do
    with {:ok, data} <- :ssl.recv(socket, 0, 5_000) do
      read_body(socket, request_line, buffer <> data, length)
    end
  end

  defp content_length(headers) do
    Enum.find_value(headers, 0, fn header ->
      case String.split(String.downcase(header), ": ", parts: 2) do
        ["content-length", value] -> String.to_integer(value)
        _other -> nil
      end
    end)
  end

  defp file(directory, name), do: directory |> Path.join(name) |> String.to_charlist()
end
