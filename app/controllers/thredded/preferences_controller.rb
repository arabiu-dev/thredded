# frozen_string_literal: true

module Thredded
  class PreferencesController < Thredded::ApplicationController
    before_action :thredded_require_login!,
                  :init_preferences

    def edit
      respond_to do |format|
        format.html # Normal HTML response, nothing changes here
        format.json { render json: serialized_preferences }
      end
    end

    def update
      if @preferences.save
        respond_to do |format|
          format.html do
            flash[:notice] = t('thredded.preferences.updated_notice')
            redirect_back fallback_location: edit_preferences_url(@preferences.messageboard)
          end
          format.json {
            render json: { message: 'Preferences updated successfully', preferences: serialized_preferences },
                   status: :ok
          }
        end
      else
        respond_to do |format|
          format.html { render :edit }
          p @preferences.errors
          format.json { render json: @preferences.errors, status: :unprocessable_entity }
        end
      end
    end

    private

    def init_preferences
      @user_preference = Thredded::UserPreference.find_or_initialize_by(user_id: thredded_current_user.id)

      if params[:messageboard_id]
        @messageboard = Thredded::Messageboard.friendly.find(params[:messageboard_id])
        @messageboard_preference = Thredded::UserMessageboardPreference.find_or_initialize_by(
          user_id: thredded_current_user.id,
          messageboard_id: @messageboard.id
        )
      end

      @preferences = Thredded::UserPreferencesForm.new(
        user: thredded_current_user,
        messageboard: messageboard_or_nil,
        messageboards: policy_scope(Thredded::Messageboard.all),
        params: preferences_params
      )
    end

    def preferences_params
      params.fetch(:user_preferences_form, {}).permit(
        :auto_follow_topics,
        :messageboard_auto_follow_topics,
        :follow_topics_on_mention,
        :messageboard_follow_topics_on_mention,
        messageboard_notifications_for_followed_topics_attributes: %i[notifier_key id messageboard_id enabled],
        notifications_for_followed_topics_attributes: %i[notifier_key id enabled],
        notifications_for_private_topics_attributes: %i[notifier_key id enabled]
      )
    end

    def serialized_preferences
      if @messageboard
        {
          user_preferences: serialized_user_preferences,
          messageboard_preference: serialized_messageboard_preference
        }
      else
        {
          user_preferences: serialized_user_preferences
        }
      end
    end

    def serialized_user_preferences
      {
        auto_follow_topics: @user_preference.auto_follow_topics,
        follow_topics_on_mention: @user_preference.follow_topics_on_mention,
        notifications_for_followed_topics: @user_preference.notifications_for_followed_topics.map do |notification|
          {
            notifier_key: notification.notifier_key,
            enabled: notification.enabled,
            id: notification.id
          }
        end
      }
    end

    def serialized_messageboard_preference
      {
        messageboard_id: @messageboard_preference.messageboard_id,
        auto_follow_topics: @messageboard_preference.auto_follow_topics,
        follow_topics_on_mention: @messageboard_preference.follow_topics_on_mention,
        notifications_for_followed_topics: serialized_notifications_for_followed_topics(@messageboard.id)

      }
    end

    def serialized_notifications_for_followed_topics(messageboard_id = nil)
      notifications = @user_preference.messageboard_notifications_for_followed_topics
      p notifications
      notifications = notifications.where(messageboard_id: messageboard_id) if messageboard_id
      notifications.map do |notification|
        {
          notifier_key: notification.notifier_key,
          enabled: notification.enabled,
          id: notification.id
        }
      end
    end
  end
end
