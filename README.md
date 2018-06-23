# ![RealWorld Example App](logo.png)

[![Build status](https://badge.buildkite.com/e93e6a16cd2ac665d56a05e535f5b49be8c433d34cf4fe4a3a.svg)](https://buildkite.com/brad-parker/servant-beam-realworld-example-app)

> ### A Servant and Beam codebase containing real world examples (CRUD, auth, advanced patterns, etc) that adheres to the [RealWorld](https://github.com/gothinkster/realworld) spec and API.

### [Demo](https://github.com/gothinkster/realworld) [RealWorld](https://github.com/gothinkster/realworld)

This codebase was created to demonstrate a fully fledged fullstack application built with **Servant and Beam** including CRUD operations, authentication, routing, pagination, and more.

We've gone to great lengths to adhere to the **Haskell** community styleguides & best practices.

For more information on how to this works with other frontends/backends, head over to the [RealWorld](https://github.com/gothinkster/realworld) repo.

# Getting started

1. Use Nix to get all the Haskell package and application dependencies you need.

  ```
  $ nix-shell
  ```

2. Create .envrc from example and allow contents

  ```
  $ cp .envrc.example .envrc
  $ direnv allow
  ```

3. Setup the database.

  ```
  $ database/scripts/setup
  ```

4. Run the test suite.

  ```
  $ cabal test
  ```

  You can run these in a watch mode using ghcid:

  ```
  $ dev/watch-tests
  ```
