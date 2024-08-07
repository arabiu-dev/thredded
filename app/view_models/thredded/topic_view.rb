# frozen_string_literal: true

module Thredded
  # A view model for Topic.
  class TopicView < Thredded::BaseTopicView
    delegate :sticky?, :locked?, :categories, :id, :blocked?, :last_moderation_record, :followers,
             :last_post, :messageboard_id, :messageboard_name,
             to: :@topic

    # @param [Topic] topic
    # @param [UserTopicReadState, NullUserTopicReadState, nil] read_state
    # @param [#destroy?] policy
    def initialize(topic, read_state, follow, policy)
      super(topic, read_state, policy)
      @follow = follow
    end

    def self.from_user(topic, user)
      read_state = follow = nil
      if user && !user.thredded_anonymous?
        read_state = Thredded::UserTopicReadState.find_by(user_id: user.id, postable_id: topic.id)
        follow = Thredded::UserTopicFollow.find_by(user_id: user.id, topic_id: topic.id)
      end
      new(topic, read_state, follow, Pundit.policy!(user, topic))
    end

    def states
      super + [
        (:locked if @topic.locked?),
        (:sticky if @topic.sticky?),
        (@follow ? :following : :notfollowing)
      ].compact
    end

    def as_json(options = {})
      {
        topic: @topic.as_json( include: {
          user: {only: [:first_name, :last_name, :full_name, :avatar_url, :job_title, :id]}
        }),
        url_path: build_url_path,
        follow: @follow.as_json,
      }
    end

    def build_url_path
      # Build the URL path using available slugs
      # Ensure that each model has a 'slug' field and that relationships are set up to access these
      topic_slug = @topic.slug
      messageboard_slug = @topic.messageboard&.slug
      messageboard_group_name = @topic.messageboard&.group&.name

      # Construct the URL path based on the application's routing scheme
      # This example assumes a nested routing structure: /groups/:group_slug/messageboards/:messageboard_slug/topics/:topic_slug
      "/channel/#{messageboard_slug}/#{topic_slug}?channel=#{messageboard_group_name}"
    end

    # @return [Boolean] whether the topic is followed by the current user.
    def followed?
      !!@follow # rubocop:disable Style/DoubleNegation
    end

    def follow_reason
      @follow.try(:reason)
    end

    def can_moderate?
      @policy.moderate?
    end

    def edit_path
      Thredded::UrlsHelper.edit_messageboard_topic_path(@topic.messageboard, @topic)
    end

    def destroy_path
      Thredded::UrlsHelper.messageboard_topic_path(@topic.messageboard, @topic)
    end

    def follow_path
      Thredded::UrlsHelper.follow_messageboard_topic_path(@topic.messageboard, @topic)
    end

    def unfollow_path
      Thredded::UrlsHelper.unfollow_messageboard_topic_path(@topic.messageboard, @topic)
    end

    def messageboard_path
      Thredded::UrlsHelper.messageboard_topics_path(@topic.messageboard)
    end
  end
end
