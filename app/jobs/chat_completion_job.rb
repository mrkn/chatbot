require "slack_bot/utils"
require "utils"

class ChatCompletionJob < ApplicationJob
  queue_as :default

  DEFAULT_PROMPT = <<~END_PROMPT
  You are ChatGPT, a large language model trained by OpenAI.
  Answer as concisely as possible.
  Current date: {current_date}
  END_PROMPT

  DEFAULT_REACTION_SYMBOL = "hourglass_flowing_sand".freeze
  REACTION_SYMBOL = ENV.fetch("SLACK_REACTION_SYMBOL", DEFAULT_REACTION_SYMBOL)

  def perform(params)
    if params["message_id"].blank?
      logger.warn "Empty message_id is given"
      return
    end

    message = Message.find(params["message_id"])
    if message.blank?
      logger.warn "Unable to find Message with id=#{message_id}"
      return
    end

    if message.query.present?
      logger.warn "Message with id=#{message.id} already has its query and response"
      return
    end

    start_query(message)

    # TODO: construct the prompt when the first query in a conversation
    #
    # if message.slack_ts == message.slack_thread_ts
       prompt = DEFAULT_PROMPT
       messages = make_first_messages(prompt, message.text)
       model = "gpt-3.5-turbo"
       temperature = 0.7
    # else
    #   # TODO: build chat context
    #   messages = [{ "role" => "user", "content" => query_body }]
    # end

    query = Query.new(
      message: message,
      text: messages[-1][:content],
      body: {
        parameters: {
          model: model,
          messages: messages,
          temperature: temperature
        }
      }
    )
    # TODO: resolve the duplicate of the above query construction and Utils.chat_completion method.
    # The best way may be making Utils.chat_completion a Query's instance method.

    chat_response = Utils.chat_completion(*messages, model:, temperature:)
    logger.info "Chat Response:\n" + chat_response.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")

    # {"id"=>"chatcmpl-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    #  "object"=>"chat.completion",
    #  "created"=>1679624074,
    #  "model"=>"gpt-3.5-turbo-0301",
    #  "usage"=>{"prompt_tokens"=>73, "completion_tokens"=>77, "total_tokens"=>150},
    #  "choices"=>
    #   [{"message"=>
    #      {"role"=>"assistant",
    #       "content"=>
    #        "はい、正しいです。ChatGPTはオープンAIによってトレーニングされた大規模な言語モデルであり、インターネットから情報を取得することができます。現在の日付は2023年3月24日です。"},
    #     "finish_reason"=>"stop",
    #     "index"=>0}]}

    response = Response.new(
      query: query,
      text: chat_response.dig("choices", 0, "message", "content").strip,
      n_query_tokens: chat_response.dig("usage", "prompt_tokens"),
      n_response_tokens: chat_response.dig("usage", "completion_tokens"),
      body: chat_response.to_json
    )

    Query.transaction do
      query.save!
      response.save!
    end

    # TODO: make the following response creation into Response's instance method

    model = chat_response["model"]
    answer = "<@#{message.user.slack_id}> #{response.text}"
    post_params = SlackBot.format_chat_gpt_response(
      answer,
      prompt_tokens: response.n_query_tokens,
      completion_tokens: response.n_response_tokens,
      model: model
    )

    posted_message = Utils.post_message(
      channel: message.conversation.slack_id,
      thread_ts: message.slack_thread_ts,
      **post_params
    )
    logger.info posted_message.inspect

    finish_query(message)
  end

  private def make_first_messages(prompt, query_body, model: "gpt-3.5-turbo")
    content = <<~END_MESSAGE
    #{prompt}

    #{query_body}
    END_MESSAGE
    content.gsub!('{current_date}', Time.now.strftime("%Y-%m-%d"))
    [{role: "user", content: content.strip}]
  end

  private def start_query(message, name=REACTION_SYMBOL)
    client = Slack::Web::Client.new
    client.reactions_add(channel: message.conversation.slack_id, timestamp: message.slack_ts, name:)
  rescue
    nil
  end

  private def finish_query(message, name=REACTION_SYMBOL)
    client = Slack::Web::Client.new
    client.reactions_remove(channel: message.conversation.slack_id, timestamp: message.slack_ts, name:)
  rescue
    nil
  end
end
