defmodule GenWebsocket do
  @moduledoc ~S"""
  A Websocket client for Elixir with a API similar to `:gen_tcp`.

  Example of usage where a client is started and connected, then it is used to send and receive
  data:
      iex> {:ok, client} = GenWebsocket.connect('example.com', 80, [])
      iex> :ok = GenWebsocket.send(client, "data")
      iex> {:ok, data} = GenWebsocket.recv(client, 100)

  When the client has the option `:active` set to `true` or `:once` it will send to the process
  that started the client or the controlling process defined with `controlling_process/2` function
  messages with the format `{:websocket, pid, data}`, where `pid` is the PID of the client and
  `data` is a binary with the data received from the websocket server. If the the `:active` option
  was set to `:once` the client will set it to `false` after sending data once. When the option is
  set to `false`, the `recv/3` function must be used to retrieve data or the option needs to be set
  back to `true` or `:once` using the `set_active/2` function.

  When the connection is lost unexpectedly a message is sent with the format
  `{:websocket_closed, pid}`.

  To close the client connection to the websocket server the function `close/1` can be used, the
  connection to the websocket will be closed and the client process will be stopped.
  """

  alias GenWebsocket.Client

  @type reason() :: any()
  @type opts() :: Keyword.t()

  @doc """
  Starts and connects a client to the websocket server.

  The `opts` paramameter is a Keyword list that expects the follwing optional entries:

  * `:transport - An atom with the transport protocol, either `:tcp` or `:tls`, defaults to `:tcp`
  * `:path` - A string with the websocket server path, defaults to `"/"`
  * `:headers` - A list of tuples with the HTTP headers to send to the server, defaults to `[]`
  * `:active` - A boolean or to indicate if the client should send back any received data, it can
  be `true`, `false` and `:once`, defaults to `false`
  * `:compress` - A boolean to indicate if the data should be compressed, defaults to `true`
  * `:protocols` - A list of strings indicating the protocols used by the server, defaults to `[]`
  """
  @spec connect(charlist(), :inet.port_number(), opts(), timeout()) ::
          {:ok, pid()} | {:error, reason()}
  defdelegate connect(host, port, opts \\ [], timeout \\ 5_000), to: Client

  @doc """
  Sends data to the websocket server.

  Data must be a binary or a list of binaries.
  """
  @spec send(pid(), iodata()) :: :ok | {:error, reason()}
  defdelegate send(client, data), to: Client

  @doc """
  When the client has the option `:active` set to `false`, the `recv/3` function can be used to
  retrieve any data sent by the server.

  If the provided length is `0`, it returns immediately with all data present in the client, even if
  there is none. If the timeout expires it returns `{:error, :timeout}`.
  """
  @spec recv(pid(), non_neg_integer(), timeout()) :: {:ok, String.t()} | {:error, reason()}
  defdelegate recv(client, length, timeout \\ 5_000), to: Client

  @doc """
  Defines the process to which the data received by the client is sent to, when the client option
  `:active` is set to `true` or `:once`.
  """
  @spec controlling_process(pid(), pid()) :: :ok | {:error, reason()}
  defdelegate controlling_process(client, pid), to: Client

  @doc """
  Closes the client connection to the websocket server and stops the client. Any data retained by
  the client will be lost.
  """
  @spec close(pid()) :: :ok
  defdelegate close(client), to: Client

  @doc """
  It defines the client `:active` option.

  The possible values for the `:active` options are `true`, `false` or `:once`. When the `:active`
  option is set to `:once`, the client will send back the first received frame of data and set the
  `:active` option to `false`.
  """
  @spec set_active(pid(), boolean() | :once) :: :ok | {:error, reason()}
  defdelegate set_active(client, active), to: Client
end
