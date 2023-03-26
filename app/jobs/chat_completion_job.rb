require "slack_bot/utils"
require "utils"

class ChatCompletionJob < ApplicationJob
  queue_as :default

  DEFAULT_PROMPT = <<~END_PROMPT
  You are ChatGPT, a large language model trained by OpenAI.
  Answer as concisely as possible.
  Current date: {current_date}
  END_PROMPT

  def perform(params)
    channel = params["channel"]
    user = params["user"]
    query_body = params["message"]
    query_ts = params["ts"]
    thread_ts = params["thread_ts"] || query_ts

    # TODO: construct the prompt when the first query in a conversation
    #
    # conversation = Conversation.find_by_slack_ts(thread_ts)
    # if conversation.blank?
    #   channel = Channel.find_by_slack_id(channel)
    #   prompt = channel.prompt&.content || channel.team.prompt&.content || DEFAULT_PROMPT
    #   conversation = Conversation.create!(channel: channel, slack_ts: thread_ts, prompt: prompt)
       prompt = DEFAULT_PROMPT
       messages = make_first_messages(prompt, query_body)
    # else
    #   messages = [{ "role" => "user", "content" => query_body }]
    # end

    response = Utils.chat_completion(*messages)
    logger.info "Chat Response:\n" + response.pretty_inspect.each_line.map {|l| "> #{l}" }.join("")

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

    model = response["model"]
    prompt_tokens = response.dig("usage", "prompt_tokens")
    completion_tokens = response.dig("usage", "completion_tokens")
    response_content = response.dig("choices", 0, "message", "content").strip
    answer = "<@#{user}> #{response_content}"
    post_params = SlackBot.format_chat_gpt_response(answer, prompt_tokens: prompt_tokens, completion_tokens: completion_tokens, model: model)

    posted_message = Utils.post_message(channel: channel, thread_ts: thread_ts, **post_params)
    logger.info posted_message.inspect

    # TODO: save data
    # query = Query.find_by_slack_ts(query_ts)
    # response = query.new_response(content: posted_message.message.text,
    #                               slack_ts: posted_message.message.ts)
    # response.save!
  end

  private

  def make_first_messages(prompt, query_body, model: "gpt-3.5-turbo")
    content = <<~END_MESSAGE
    #{prompt}

    #{query_body}
    END_MESSAGE
    content.gsub!('{current_date}', Time.now.strftime("%Y-%m-%d"))
    [{role: "user", content: content.strip}]
  end
end
