# GenWebsocket

A websocket client based on [gun](https://github.com/ninenines/gun) with a similar API to [gen_tcp](http://erlang.org/doc/man/gen_tcp.html).

## Installation

The package can be installed by adding `gen_websocket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gen_websocket, "~> 0.1.0"}
  ]
end
```

## Usage

Below is a small example on how you can start a client and use it to send and receive data, and how to stop the client. See the full docs at https://hexdocs.pm/gen_websocket for more information.

```elixir
{:ok, client} = GenWebsocket.connect('echo.websocket.org', 80)
:ok = GenWebsocket.send(client, "data")
{:ok, "data"} = GenWebsocket.recv(client, 0)
:ok = GenWebsocket.close(client)
```

## Contributing

Contributions are welcome! Feel free to open an issue if you'd like to discuss a problem or a possible solution. Pull requests are much appreciated.
