[![Build Status](https://secure.travis-ci.org/hazardfn/riemannx.svg?branch=master "Build Status")](http://travis-ci.org/hazardfn/riemannx)
[![Coverage Status](https://coveralls.io/repos/github/hazardfn/riemannx/badge.svg?branch=master)](https://coveralls.io/github/hazardfn/riemannx?branch=master)

Riemannx
========

Riemannx is a simple riemann client with UDP and TCP support, it also supports
a combined backend which favours UDP when possible and falls back to TCP when
not (based on your max UDP packet size).

I was having a lot of performance problems with the elixir-riemann client 
currently available so decided to go back to basics with good old fashioned
pool boy, UDP support is also a plus.

This is a functional WIP and haven't set up any pipelines as of yet, 
watch this space.

### Acknowledgements

A large portion of code has been borrowed from the  [elixir-riemann client](https://github.com/koudelka/elixir-riemann).
