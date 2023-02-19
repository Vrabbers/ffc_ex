FROM elixir:1.14 AS build

RUN mkdir /app
WORKDIR /app

ENV MIX_ENV=prod
ENV BOT_TOKEN=dummy

COPY . .
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get

CMD ["mix", "run", "--no-halt"]
