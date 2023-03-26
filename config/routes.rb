require "slack_bot/app"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  namespace :slack do
  end

  mount SlackBot::Application, at: "/slack"
end
