module Utils
  module_function def chat_completion(*messages, model: nil, temperature: nil)
    body = {
      parameters: {
        model: model || "gpt-3.5-turbo",
        messages: messages,
        temperature: temperature || 0.7
      }
    }

    client = OpenAI::Client.new
    response = client.chat(params)

    Response.create!(
      query: query,
    )

    response
  end

  module_function def post_message(channel:, text:, **params)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: text, **params)
  end

  module_function def post_ephemeral(channel:, user:, text:, **params)
    slack_client = Slack::Web::Client.new
    slack_client.chat_postEphemeral(channel: channel, user: user, text: text, **params)
  end
end
