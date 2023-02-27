FROM elixir:1.14-alpine AS build

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git

ENV MIX_ENV=prod

COPY . .
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get
RUN mix release

FROM alpine:3.17 AS final

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add libstdc++ ncurses openssl

COPY --from=build /app/_build/prod/rel/ffc_ex .

CMD ["bin/ffc_ex", "start"]
