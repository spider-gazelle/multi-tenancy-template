# Spider-Gazelle Multitenancy Starter

[![CI](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml/badge.svg)](https://github.com/spider-gazelle/multi-tenancy-template/actions/workflows/ci.yml)

Clone this repository to start building your own spider-gazelle based application.
This is a template and as such, Do What the Fuck You Want To

## Documentation

This builds on the basic Spider-Gazelle template to provide a good starting point for building a postresql backed application.

## Testing

Launch the test script which leverages docker configure an isolated test environment for your specs.

`./test`

alternatively you can run `docker compose up` directly

## Compiling

`crystal build ./src/app.cr`

or

`shards build`

### Deploying

Once compiled you are left with a binary `./app`

* for help `./app --help`
* viewing routes `./app --routes`
* run on a different port or host `./app -b 0.0.0.0 -p 80`
