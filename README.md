# Riemannx | [![Build Status](https://travis-ci.org/hazardfn/riemannx.svg?branch=master "Build Status")](http://travis-ci.org/hazardfn/riemannx) [![Coverage Status](https://coveralls.io/repos/github/hazardfn/riemannx/badge.svg?branch=master)](https://coveralls.io/github/hazardfn/riemannx?branch=master) [![Ebert](https://ebertapp.io/github/hazardfn/riemannx.svg)](https://ebertapp.io/github/hazardfn/riemannx) [![Hex.pm](https://img.shields.io/hexpm/dt/riemannx.svg)](https://hex.pm/packages/riemannx) [![GitHub release](https://img.shields.io/github/release/hazardfn/riemannx.svg)](https://github.com/hazardfn/riemannx/releases/latest)

> A fully featured riemann client built on the reliability of poolboy and the
> awesome power of Elixir!

<p align="center">
<img src="https://upload.wikimedia.org/wikipedia/commons/8/82/Georg_Friedrich_Bernhard_Riemann.jpeg" height="250" width="250">
</p>

## TL;DR

Riemannx is a riemann client built in elixir, currently it's the only client in elixir that supports UDP and TLS (as well as TCP). There is also a batching mode you can use that works with any of the transports.

It has an experimental combined option that makes the best of both TCP and UDP - in the combined mode UDP is the favoured approach but if the message size exceeds the max udp size set TCP will be used.

* As of 2.1.0 TLS connections are supported.
* As of 2.2.0 You can now query the index.
* As of 2.3.0 You can specify a host in config or we will work one out for you.
* As of 2.4.0 You can set a priority for the workers.
* As of 3.0.0 configuration entries are separate for the different connection types (see: [Migrating to 3.0+](#migrate-3.0)) - in all 3.x versions there is a legacy settings backend if you want to upgrade without breaking your previous setup.
* As of 4.0.0 combined batching is the default connection type and the legacy config is removed (see: [Batching](#batching)) support for time_micros was added (see: [Micro Time](#micro-time)).

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
    * [Batching](#batching)
    * [Micro Time](#micro-time)
    * [Host Injection](#host-inj)
    * [Process Priority](#prio)
    * [Migrating to 3.0+](#migrate-3.0)
    * [Settings Backend](#settings-backend)
    * [Metrics Backend](#metrics-backend)
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

The client has only been battle tested on: `0.2.11`. From version 4.0.0 of the client you will need to set `use_micro` to false if you use a version of riemann older than `0.2.13` and aren't setting the time field yourself. It should work with `0.3.0` but again hasn't been formerly tested (anyone wanting to work on integration tests I would greatly appreciate it).

## 2. Installation<a name="installation"></a>

Installation happens just like any other elixir library, add it to your mix file and the rest is history:

```elixir
def deps do
  [{:riemannx, "~> 4.0"}]
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
  host: "localhost", # The riemann server
  event_host: "my_app", # You can override the host name sent to riemann if you want (see: Host Injection)
  send_timeout: 30_000, # Synchronous send timeout
  type: :batch, # The type of connection you want to run (:tcp, :udp, :tls, :combined, :batch)
  settings_module: Riemannx.Settings.Default # The backend used for reading settings back
  metrics_module: Riemannx.Metrics.Default # The backend used for sending metrics
  use_micro: true # Set to false if you use a riemann version before 0.2.13
  batch_settings: [
    type: :combined # The underlying connection to use when using batching.
    size: 50, # The size of batches to send to riemann.
    interval: {1, :seconds} # The interval at which to send batches.
  ]
  tcp: [
    port: 5555,
    retry_count: 5, # How many times to re-attempt a TCP connection
    retry_interval: 1000, # Interval to wait before the next TCP connection attempt (milliseconds).
    priority: :high, # Priority to give TCP workers.
    options: [], # Specify additional options to be passed to gen_tcp (NOTE: [:binary, nodelay: true, packet: 4, active: true] will be added to whatever you type here as they are deemed essential)
    pool_size: 5, # How many TCP workers should be in the pool.
    max_overflow: 5, # Under heavy load how many more TCP workers can be created to meet demand?
    strategy: :fifo # The poolboy strategy for retrieving workers from the queue
  ],
  udp: [
    port: 5555,
    priority: :high,
    options: [], # Specify additional options to be passed to gen_udp (NOTE: [:binary, sndbuf: max_udp_size()] will be added to whatever you type here as they are deemed essential)
    max_size: 16_384, # Maximum accepted packet size (this is configured in your Riemann server)
    pool_size: 5,
    max_overflow: 5,
    strategy: :fifo
  ],
  tls: [
    port: 5554,
    retry_count: 5, # How many times to re-attempt a TLS connection
    retry_interval: 1000, # Interval to wait before the next TLS connection attempt (milliseconds).
    priority: :high,
    options: [], # Specify additional options to be passed to :ssl (NOTE: [:binary, nodelay: true, packet: 4, active: true] will be added to whatever you type here as they are deemed essential)
    pool_size: 5,
    max_overflow: 5,
    strategy: :fifo
  ]
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
    type: :tls,
    tls: [
      port: 5554,
      retry_count: 5, # How many times to re-attempt a TLS connection
      retry_interval: 1000, # Interval to wait before the next TLS connection attempt (milliseconds).
      priority: :high,
      # SSL Opts are passed to the underlying ssl erlang interface
      # See available options here: http://erlang.org/doc/man/ssl.html
      # (NOTE: [:binary, nodelay: true, packet: 4, active: true] will be added to whatever you type here as they are deemed essential)
      options: [
        keyfile: "path/to/key",
        certfile: "path/to/cert",
        verify_peer: true
      ],
      pool_size: 5,
      max_overflow: 5,
      strategy: :fifo
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

### Batching<a name="batching"></a>

Batching as of 4.0.0 is the default connection behaviour - the default batch size is 50 and the interval is every 1 second. Batching works like so:

* Whatever is in the queue will be sent every interval.

* If the size of the queue reaches the set batch size it will be flushed regardless of interval.

There is a new type called `:batch` and a settings key called `batch_settings:`, inside batch_settings you can specify a type for the underlying connection (`:tcp`, `:udp`, `:combined`, `:tls`). As always combined is the default.

### Micro Time<a name="micro-time"></a>

From version `0.2.13` of riemann it was possible to set time in microseconds - Riemannx now supports and uses the `time_micros` field (unless you have set the time or time_micros field yourself, riemannx won't overwrite that). If you are using an older version of riemann it will only use the seconds field.

> NOTE: If you set both time and time_micros riemann will prioritise the micro time and riemannx will overwrite neither.

### Host Injection<a name="host-inj"></a>

It sounds fancier than it is but basically describes the functionality that adds a host entry to your event if you haven't specified one. There are 3 ways to specify a host:

* Do it before you send the event (add a :host key to the keyword list)

* Add the `:event_host` key to your config.

* Let riemannx do it using `:inet.gethostname()` - we only call that once and save the result, it is not called on every event.

The last 2 options are the most favourable as they will keep your code clean.

### Process Priority<a name="prio"></a>

In this client there is the opportunity to set a priority for your workers allowing you to place higher or less priority on the sending of your stats to riemann.

The difference setting a priority makes depends heavily on the hardware and how you have set your other priorities in general, more info can be found here: http://erlang.org/doc/man/erlang.html#process_flag-2

If you try to set the priority to :max riemannx will raise a RuntimeError because that is a terrible idea. It will also raise a RuntimeError if you try :foo because that is also a terrible idea.

### Migrating to 3.0+<a name="migrate-3.0"></a>

Migrating to 3.0 is essentially just a case of changing your config layout - all of the same options exist except now you have more control over your workers at the type level, this is especially valuable when using the combined setup as you could, say, have a smaller pool of TCP workers and a larger UDP worker pool instead of as it was before (2x whatever pool_size you gave).

You can see this new layout here: [Config](#config)

> If anything doesn't make sense here feel free to open an issue so we can expand the README to fix the unclarity.

### Settings Backend<a name="settings-backend"></a>

If you want to store your settings elsewhere you can create a backend to read settings from a database for example. Look at the default settings module for the required callbacks.

This can be useful if you want to store company-wide settings in one place.

> Feel free to open an issue if you have questions.

### Metrics Backend<a name="metrics-backend"></a>

Riemannx supports sending basic metrics, you can create a custom module to support any infrastructure (graphite, influx etc.). There are 3 callbacks currently:

* `udp_message_sent(size)` - informs when a udp message is sent and gives the size of the message.
* `tcp_message_sent(size)` - informs when a tcp message is sent and gives the size of the message.
* `tls_message_sent(size)` - informs when a tls message is sent and gives the size of the message.

## 5. Contributions<a name="contribute"></a>

Contributions are warmly received, check out the Projects section for some ideas I have written down and for the latest on what is underway.

### Guidelines<a name="guidelines"></a>

This repository uses the [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows#gitflow-workflow) workflow meaning *all PR's should be pointed towards the develop branch!*. Below are some things to consider before creating a PR:

* I would like to maintain test coverage at *100%!* - I may let this slide in urgent cases (bugs etc.)

* To avoid congesting Travis unnecessarily it would be appreciated if you check the following locally first:
  - `mix coveralls.html` (Aim for 100%)
  - `mix dialyzer` (Takes a while and I appreciate you can't test all erlang/elixir versions)

* I consider this client feature complete, if your PR breaks backwards compatibility completely or changes pre-existing behaviour/defaults I'd appreciate a heads up and your justifications :).

## 6. Acknowledgements<a name="ack"></a>

A portion of code has been borrowed from the original [elixir-riemann client](https://github.com/koudelka/elixir-riemann). Most of the protobuf stuff comes from there.
