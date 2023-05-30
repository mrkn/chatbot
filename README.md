# Simple ChatGPT Slack Bot

## Environment variables

* `ADMIN_USER` and `ADMIN_PASSWORD` is used for Basic Auth of Sidekiq's management console
* `ALLOW_CHANNEL_IDS` for specifying channel IDs where users can communicate with the chatbot
* `SLACK_BOT_TOKEN` is for the Slack Bot's access token
* `SLACK_SIGNING_SECRET` is for signing secret to check the request coming from Slack
* `OPENAI_ACCESS_TOKEN` is for OpenAI API Access Token
* `OPENAI_ORGANIZATION_ID` is for OpenAI API Organization ID (optional)
* `REDIS_URL` is for URL of Redis server

## Required scopes

* `app_mentions:read`
* `channels:read`
* `chat:write`
* `reactions:write`
* `users:read`
* `users:read:email`

## Model Name

When you use this with Azure OpenAI Service, you need to include `gpt35turbo`
section in the model like `abc-gpt35turbo-001`. Chatbot detects the model
version and its unit price by checking the existence of `gpt35turbo`.

## License

MIT License

## Author

Kenta Murata
