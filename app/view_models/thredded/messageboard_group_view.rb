# frozen_string_literal: true

module Thredded
  class MessageboardGroupView
    delegate :name, :id, to: :@group, allow_nil: true
    attr_reader :group, :messageboards

    def self.grouped(
      messageboards_scope, user: Thredded::NullUser.new, with_unread_topics_counts: !user.thredded_anonymous?
    )
      # Load all groups
      all_groups = Thredded::MessageboardGroup.order(:position, :id).index_by(&:id)

      # Prepare scopes and load messageboards with related data
      scope = messageboards_scope.preload(last_topic: [:last_user])
        .eager_load(:group)
        .order(Arel.sql('COALESCE(thredded_messageboard_groups.position, 0) ASC, thredded_messageboard_groups.id ASC'))
        .ordered

      topics_scope = Thredded::TopicPolicy::Scope.new(user, Thredded::Topic.all).resolve
      posts_scope = Thredded::PostPolicy::Scope.new(user, Thredded::Post.all).resolve

      # Count topics and posts
      topic_counts = topics_scope.group(:messageboard_id).count
      post_counts = posts_scope.group(:messageboard_id).count

      unread_topics_counts = {}
      unread_followed_topics_counts = {}
      if with_unread_topics_counts
        unread_topics_counts = scope.unread_topics_counts(user: user, topics_scope: topics_scope)
        unread_followed_topics_counts = scope.unread_topics_counts(
          user: user, topics_scope: topics_scope.followed_by(user)
        )
      end

      # Corrected grouping using `messageboard_group_id`
      grouped_messageboards = scope.group_by { |mb| mb.messageboard_group_id }

      # Build the array including groups with no messageboards
      all_groups.map do |group_id, group|
        messageboards = grouped_messageboards[group_id] || []
        messageboard_views = messageboards.map do |messageboard|
          MessageboardView.new(
            messageboard,
            topics_count: topic_counts[messageboard.id] || 0,
            posts_count: post_counts[messageboard.id] || 0,
            unread_topics_count: unread_topics_counts[messageboard.id] || 0,
            unread_followed_topics_count: unread_followed_topics_counts[messageboard.id] || 0
          )
        end
        new(group, messageboard_views)
      end
    end

    def initialize(group, messageboards)
      @group = group
      @messageboards = messageboards
    end
  end
end
