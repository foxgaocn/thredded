# frozen_string_literal: true
# Backend
require 'pundit'
require 'active_record_union'
require 'db_text_search'
require 'friendly_id'
require 'html/pipeline'
require 'html/pipeline/sanitization_filter'
require 'html/pipeline/vimeo/vimeo_filter'
require 'html/pipeline/youtube/youtube_filter'
require 'rinku'
require 'kaminari'
require 'rb-gravatar'
require 'active_job'
require 'inline_svg'

# Require these explictly to make sure they are not reloaded.
# This allows for configuring them by accessing class methods in the initializer.
require 'thredded/html_pipeline/at_mention_filter'
require 'thredded/html_pipeline/autolink_filter'
require 'thredded/html_pipeline/kramdown_filter'

# Asset compilation
require 'autoprefixer-rails'
require 'autosize/rails'
require 'jquery/rails'
require 'rails-timeago'
require 'select2-rails'
require 'sprockets/es6'

require 'thredded/engine'

module Thredded
  mattr_accessor \
    :autocomplete_min_length,
    :active_user_threshold,
    :avatar_url,
    :email_from,
    :email_incoming_host,
    :email_outgoing_prefix,
    :email_reply_to,
    :layout,
    :messageboards_order,
    :user_class,
    :user_display_name_method,
    :user_name_column,
    :user_path,
    :text_search_config

  # @return [Symbol] The name of the method used by Thredded controllers and views to fetch the currently signed-in user
  mattr_accessor :current_user_method

  # @return [Symbol] The name of the moderator flag column on the users table for the default permissions model
  mattr_accessor :moderator_column

  # @return [Symbol] The name of the admin flag column on the users table for the default permissions model
  mattr_accessor :admin_column

  # @return [Boolean] Whether posts that are pending moderation are visible to regular users.
  mattr_accessor :content_visible_while_pending_moderation

  # @return [Boolean] Whether users that are following a topic are listed on topic page.
  mattr_accessor :show_topic_followers

  # @return [Symbol] The name of the method used by Thredded to display users
  mattr_accessor :user_display_name_method

  self.active_user_threshold = 5.minutes
  self.admin_column = :admin
  self.avatar_url = ->(user) { Gravatar.src(user.email, 128, 'mm') }
  self.email_reply_to = -> (postable) { "#{postable.hash_id}@#{Thredded.email_incoming_host}" }
  self.layout = 'thredded/application'
  self.moderator_column = :admin
  self.user_name_column = :name
  self.content_visible_while_pending_moderation = true
  self.show_topic_followers = false
  self.messageboards_order = :position
  self.autocomplete_min_length = 2
  self.text_search_config = 'english'

  # @return [Thredded::AllViewHooks] View hooks configuration.
  def self.view_hooks
    instance = Thredded::AllViewHooks.instance
    unless instance
      fail '`Thredded.view_hooks` must be configured in a `Rails.application.config.to_prepare` block!'
    end
    instance
  end

  def self.user_display_name_method
    @@user_display_name_method || user_name_column
  end

  # @param value [:position, :topics_count_desc, :last_post_at_desc]
  def self.messageboards_order=(value)
    case value
    when :position, :topics_count_desc, :last_post_at_desc
      @@messageboards_order = value # rubocop:disable Style/ClassVars
    else
      fail ArgumentError, "Unexpected value for Thredded.messageboards_order: #{value}"
    end
  end

  # @return [Class<Thredded::UserExtender>] the user class from the host application.
  def self.user_class
    fail 'Please use a string instead of a class' if @@user_class.is_a?(Class)

    if @@user_class.is_a?(String)
      begin
        Object.const_get(@@user_class)
      rescue NameError
        @@user_class.constantize
      end
    end
  end

  # @param view_context [Object] context to execute the lambda in.
  # @param user [Thredded.user_class]
  # @return [String] path to the user evaluated in the specified context.
  def self.user_path(view_context, user)
    view_context.instance_exec(user, &@@user_path)
  end

  # Whether the layout is a thredded layout as opposed to the application layout.
  def self.standalone_layout?
    layout.is_a?(String) && layout.start_with?('thredded/')
  end

  # Returns a view for the given posts' scope, applying read permission filters to the scope.
  # Can be used in main_app, e.g. for showing the recent user posts on the profile page.
  #
  # @param scope [ActiveRecord::Relation<Thredded::Post>] the posts scope for which to return the view.
  # @param current_user [Thredded.user_class, nil] the user viewing the posts.
  # @return [PostsPageView]
  def self.posts_page_view(scope:, current_user:)
    current_user ||= Thredded::NullUser.new
    PostsPageView.new(
      current_user,
      Pundit.policy_scope!(current_user, scope)
        .where(messageboard_id: Pundit.policy_scope!(current_user, Thredded::Messageboard.all).pluck(:id))
        .includes(:postable)
    )
  end
end
