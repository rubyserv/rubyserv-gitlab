# Plugin: GitLab
# Author: James Newton <hello@jamesnewton.com>
#
# Description: A bot to manage GitLab and get notifications from the webhooks
#
# Configuration:
#  gitlab:
#    endpoint: http://your gitlab domain/api/v3
#    private_token: a private token for the user gitlab will manage as
#    channel: #channel that notices will stream to
#
# Gems: gitlab, json

require 'json'
require 'gitlab'

module GitLab
  include RubyServ::Plugin

  configure do |config|
    config.nickname = 'GitLab'
    config.realname = 'GitLab'
    config.username = 'GitLab'
    config.channels = [RubyServ.config.gitlab.channel]
    config.database = 'gitlab'
  end

  before :setup_gitlab
  before :setup_database

  web :post, '/gitlab/system_notices' do |m|
    join_target_channel_if_not_there(m, params[:channel])

    payload = JSON.parse(request.body.read, symbolize_names: true)
    notice  = case payload[:event_name]
              when 'project_create'        then "Project: event: created - name: %{name} - owner: %{owner_name} <%{owner_email}> - #{RubyServ.config.gitlab.endpoint.sub('api/v3', '')}%{path_with_namespace}" % payload
              when 'project_destroy'       then "Project: event: destroyed - name: %{name} - owner: %{owner_name} <%{owner_email}> - #{RubyServ.config.gitlab.endpoint.sub('api/v3', '')}%{path_with_namespace}" % payload
              when 'user_add_to_team'      then "User: event: added to team - name: %{project_name} (%{project_path}) - user: %{user_name} <%{user_email}> - access: %{project_access}" % payload
              when 'user_remove_from_team' then "User: event: removed from team - name: %{project_name} (%{project_path}) - user: %{user_name} <%{user_email}> - access: %{project_access}" % payload
              when 'user_create'           then "User: event: created - name: %{name} <%{email}>" % payload
              when 'user_destroy'          then "User: event: destroyed - name: %{name} <%{email}>" % payload
              end

    m.client.message(RubyServ.config.gitlab.channel, notice)
  end

  web :post, '/gitlab/project_notices' do |m|
    join_target_channel_if_not_there(m, params[:channel])

    payload = JSON.parse(request.body.read, symbolize_names: true)

    payload[:commits].each do |commit|
      message = "\x02%s:\x02 \x033%s <%s>\x03 \x038%s\x03 * \x02%s\x02: %s" % [payload[:repository][:name], commit[:author][:name], commit[:author][:email], payload[:ref].gsub('refs/heads/', ''), commit[:id][0..8], commit[:message]]

      m.client.message("##{params[:channel]}", message)
    end
  end

  match(/set (\S+) (\S+)/) do |m, command, value|
    case command
    when 'token'
      set_token(m, value)

      m.reply 'Token set.'
    end
  end

  def setup_gitlab
    config = RubyServ.config.gitlab

    Gitlab.configure do |c|
      c.endpoint      = config.endpoint
      c.user_agent    = 'RubyServ'
    end
  end

  def gitlab(token)
    Gitlab.private_token = token
    Gitlab
  end

  def join_target_channel_if_not_there(m, channel)
    m.client.join("##{channel}", true) unless RubyServ::IRC::Channel.find("##{channel}").users.include?(m.client.user)
  end

  def setup_database
    if database.users.nil?
      database.users = []
      database.save
    end
  end

  def find_user(m)
    database.users.select { |hash| hash[:login] == m.user.login }.first
  end

  def set_token(m, value)
    if user = find_user(m)
      database.users[database.users.index { |hash| hash == user }] = user.merge(key: value)
    else
      database.users << { login: m.user.login, key: value }
    end

    database.save
  end
end
