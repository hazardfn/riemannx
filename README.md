# Riemannx | [![Build Status](https://travis-ci.org/hazardfn/riemannx.svg?branch=master "Build Status")](http://travis-ci.org/hazardfn/riemannx) [![Coverage Status](https://coveralls.io/repos/github/hazardfn/riemannx/badge.svg?branch=master)](https://coveralls.io/github/hazardfn/riemannx?branch=master) [![Ebert](https://ebertapp.io/github/hazardfn/riemannx.svg)](https://ebertapp.io/github/hazardfn/riemannx) [![Hex.pm](https://img.shields.io/hexpm/dt/riemannx.svg)](https://hex.pm/packages/riemannx) [![GitHub release](https://img.shields.io/github/release/hazardfn/riemannx.svg)](https://github.com/hazardfn/riemannx/releases/latest)

> A fully featured riemann client built on the reliability of poolboy and the
> awesome power of Elixir!

<p align="center">
<img src="https://upload.wikimedia.org/wikipedia/commons/8/82/Georg_Friedrich_Bernhard_Riemann.jpeg" height="250" width="250">
</p>

## TL;DR

Riemannx is a riemann client built in elixir, currently it's the only client in elixir that supports UDP. It has an experimental combined option that makes the best of both TCP and UDP - in the combined mode UDP is the favoured approach but if the message size exceeds the max udp size set TCP will be used.

As of 2.1.0 TLS connections are supported.
As of 2.2.0 you can now query the index.

## Contents

1. [Prerequisites](#prerequisites)
    * [Erlang](#erlang)
    * [Elixir](#elixir)
    * [Riemann](#riemann)
2. [Installation](#installation)
3. [Examples](#examples)
    * [Config](#config)
    * [Synchronous](#sync)
    * [Asynchronous](#async)
    * [TLS](#tls)
    * [Querying the index](#querying)
4. [Special Notes](#special)
    * [Host Injection](#host-inj)
5. [Contributions](#contribute)
6. [Acknowledgements](#ack)

## 1. Prerequisites<a name="prerequisites"></a>

As always there are prerequisites required before using Riemannx, most of these are obvious (elixir, erlang) but contain some information on which versions are tested and supported.

### Erlang<a name="erlang"></a>

Currently all erlang versions ~> 18 are supported. This includes 20, 20.1 is not yet tested but I foresee no great problems there.

Tested by travis:

* OTP: `18.0`
* OTP: `19.3`
* OTP: `20.0`

### Elixir<a name="elixir"></a>

I have tried to ensure compatibility from 1.3.4 onwards and will continue to do so where appropriate. Tested combinations:

* OTP: `18.0` Elixir: `1.3.4 / 1.4.5 / 1.5.1`
* OTP: `19.3` Elixir: `1.3.4 / 1.4.5 / 1.5.1`
* OTP: `20.0` Elixir: `1.4.5 / 1.5.1`

### Riemann<a name="riemann"></a>

As is often the case, a client is fairly useless without it's server counterpart - for more information about riemann visit http://riemann.io.

The client has only been battle tested on: `0.2.11`. It should work with the latest `0.2.14` but has not been tested.

## 2. Installation<a name="installation"></a>

Installation happens just like any other elixir library, add it to your mix file and the rest is history:

```elixir
def deps do
  [{:riemannx, "~> 2.3"}]
end
```

Make sure you add riemannx to the applications list in your mix.exs file also, this ensures it is started with your app and that it will be included in your releases (if you use a release manager):

```elixir
applications: [:logger, :riemannx]
```

## 3. Examples<a name="examples"></a>

To use riemannx all you need to do is fill out some config entries - after that everything just happens automagically (save for the actual sending of course). Below is a comprehensive list of available options:

### Config<a name="config"></a>

```elixir
config :riemannx, [
  # Client settings
  host: "127.0.0.1",
  tcp_port: 5555,
  udp_port: 5555,
  max_udp_size: 16384, # Must be the same as server side, the default is riemann's default.
  event_host: "test_host" # If you don't set this riemannx will use :inet.gethostname()
  type: :combined, # A choice of :tcp, :udp, :combined or :tls
  retry_count: 5, # How many times to re-attempt a TCP connection before crashing.
  retry_interval: 1, # Interval to wait before the next TCP connection attempt.
  ssl_opts: [], # Used for tls, see TLS section for details.

  # Poolboy settings
  pool_size: 5, # Pool size will be 5x2 (10) if you use a combined type.
  max_overflow: 5, # Max overflow will be 5x2 (10) if you use a combined type.
  strategy: :fifo, # See Riemannx.Settings documentation for more info.
]
```

Riemannx supports two `send` methods, one asynchronous the other synchronous:

### Synchronous Send<a name="sync"></a>

Synchronous sending allows you to handle the errors that might occur during send, below is an example showing both how this error looks and what happens on a successful send:

```elixir
event = [service: "riemannx-elixir",
         metric: 1,
         attributes: [a: 1],
         description: "test"]

case Riemannx.send(event) do
  :ok ->
    "Success!"

  [error: error, msg: encoded_msg] ->
    # The error will always be a string so you can output it as it is.
    #
    # The encoded message is a binary blob but you can use the riemannx proto
    # msg module to decode it if you wish to see it in human readable form.
    msg = encoded_msg |> Riemannx.Proto.Msg.decode()
    Logger.warn("Error: #{error} Message: #{inspect msg}")
end
```

### Asynchronous Send<a name="async"></a>

Asynchronous sending is much faster but you never really know if your message made it, in a lot of cases this kind of sending is safe enough and for most use cases the recommended choice. It's fairly simple to implement:

```elixir
event = [service: "riemannx-elixir",
         metric: 1,
         attributes: [a: 1],
         description: "test"]

Riemannx.send_async(event)

# Who knows if it made it? Who cares? 60% of the time it works everytime!
```

> NOTE: If a worker is unable to send it will die and be restarted giving it a chance to return to a 'correct' state. On an asynchronous send this is done by pattern matching :ok with the send command, for synchronous sends if the return value is an error we kill the worker before returning the result.

### TLS<a name="tls"></a>

TLS support allows you to use a secure TCP connection with your riemann server, to learn more about how to set this up take a look here: [Secure Riemann Traffic Using TLS](http://riemann.io/howto.html#securing-traffic-using-tls)

If you choose to use TLS you will be using a purely TCP setup, combined is not supported (and shouldn't be either) with TLS:

```elixir
  config :riemannx, [
    host: "127.0.0.1",
    tcp_port: 5555,
    type: :tls,
    # SSL Opts are passed to the underlying ssl erlang interface
    # See available options here: http://erlang.org/doc/man/ssl.html
    ssl_opts: [
      keyfile: "path/to/key",
      certfile: "path/to/cert",
      verify_peer: true
    ]
  ]
```
Assuming you have set up the server-side correctly this should be all you need to get started.

### Querying the index<a name="querying"></a>

Riemann has the concept of a queryable index which allows you to search for specific events, indexes must be specially created in your config otherwise the server will return a "no index" error.

```elixir
# Lets send an event that we can then query
Riemannx.send([service: "riemannx", metric: 5.0, attributes: [v: "2.2.0"]])

# Let's fish it out
events = Riemannx.query('service ~= "riemannx"')

#  [%{attributes: %{"v" => "2.2.0"}, description: nil, host: _,
#     metric: nil, service: "riemannx", state: nil, tags: [],
#     time: _, ttl: _}]
```

For more information on querying and the language features have a look at the [Core Concepts](http://riemann.io/concepts.html).

## 4. Special Notes<a name="special"></a>

This section contains some notes on the behaviour of riemannx that may interest you or answer questions you have about certain things.

### Host Injection<a name="host-inj"></a>

It sounds fancier than it is but basically describes the functionality that adds a host entry to your event if you haven't specified one. There are 3 ways to specify a host:

* Do it before you send the event (add a :host key to the keyword list)

* Add the `:event_host` key to your config.

* Let riemannx do it using `:inet.gethostname()` - we only call that once and save the result, it is not called on every event.

The last 2 options are the most favourable as they will keep your code clean.

## 5. Contributions<a name="contribute"></a>

Contributions are warmly received, check out the Projects section for some ideas I have written down and for the latest on what is underway.

### Guidelines<a name="guidelines"></a>

This repository uses the [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows#gitflow-workflow) workflow meaning *all PR's should be pointed towards the develop branch!*. Below are some things to consider before creating a PR:

* I would like to maintain test coverage at *100%!* - I may let this slide in urgent cases (bugs etc.)

* To avoid congesting Travis unnecessarily it would be appreciated if you check the following locally first:
  - `mix coveralls.html` (Aim for 100%)
  - `mix dialyzer` (Takes a while and I appreciate you can't test all erlang/elixir versions)

* I consider this client feature complete and fully compatible with 0.2.x versions of Riemann, if your PR adds something only 0.x.x can handle I'd appreciate a heads up.

## 6. Acknowledgements<a name="ack"></a>

A portion of code has been borrowed from the original [elixir-riemann client](https://github.com/koudelka/elixir-riemann). Most of the protobuf stuff comes from there.
