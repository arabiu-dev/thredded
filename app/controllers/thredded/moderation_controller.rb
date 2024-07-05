# frozen_string_literal: true

module Thredded
  class ModerationController < Thredded::ApplicationController
    before_action :thredded_require_login!
    before_action :thredded_require_moderator!

    # def pending
    #   @posts = Thredded::PostsPageView.new(
    #     thredded_current_user,
    #     preload_posts_for_moderation(moderatable_posts.pending_moderation).order_oldest_first
    #       .send(Kaminari.config.page_method_name, current_page)
    #       .preload_first_topic_post
    #   )
    #   maybe_set_last_moderated_record_flash
    # end

    # def history
    #   @post_moderation_records = accessible_post_moderation_records
    #     .order(created_at: :desc)
    #     .send(Kaminari.config.page_method_name, current_page)
    #     .preload(:messageboard, :post_user, :moderator, post: :postable)
    #     .preload_first_topic_post
    # end

    def pending
      @posts = Thredded::PostsPageView.new(
        thredded_current_user,
        preload_posts_for_moderation(moderatable_posts.pending_moderation).order_oldest_first
          .send(Kaminari.config.page_method_name, current_page)
          .preload_first_topic_post
      )
      maybe_set_last_moderated_record_flash

      respond_to do |format|
        format.html # Continue to render HTML as before
        format.json {
          render json: @posts.as_json(include: {
                                        posts: {
                                          only: [:id, :created_at, :updated_at],
                                          include: {
                                            user: {
                                              only: [:first_name, :last_name, :job_title, :avatar_url],
                                              methods: [:full_name] # Assuming you might have a method like full_name
                                            },
                                            topic: {
                                              only: [:title, :id] # Example for including topic details
                                            },
                                            messageboard: {
                                              only: [:name, :id] # Include messageboard details if relevant
                                            }
                                          }
                                        }
                                      })
        }
      end
    end

    def history
      @post_moderation_records = accessible_post_moderation_records
        .order(created_at: :desc)
        .send(Kaminari.config.page_method_name, current_page)
        .preload(:messageboard, :post_user, :moderator, post: :postable)
        .preload_first_topic_post
      respond_to do |format|
        format.html
        format.json {
          render json: @post_moderation_records.as_json(include: {
                                                          messageboard: {}, # Include specific fields if needed
                                                          post_user: {
                                                            only: [:first_name, :last_name, :job_title, :avatar_url]
                                                          },
                                                          moderator: {}, # Example for including only certain moderator attributes
                                                          post: {
                                                            include: {
                                                              postable: { only: [:id, :title, :content] } # Customize as per your model attributes
                                                            }
                                                          }
                                                        })
        }
      end
    end

    # def activity
    #   @posts = Thredded::PostsPageView.new(
    #     thredded_current_user,
    #     preload_posts_for_moderation(moderatable_posts).order_newest_first
    #       .send(Kaminari.config.page_method_name, current_page)
    #       .preload_first_topic_post
    #   )
    #   maybe_set_last_moderated_record_flash
    # end

    # def activity
    #   @posts = Thredded::PostsPageView.new(
    #     thredded_current_user,
    #     preload_posts_for_moderation(moderatable_posts).order_newest_first
    #       .send(Kaminari.config.page_method_name, current_page)
    #       .preload_first_topic_post
    #   )
    #   maybe_set_last_moderated_record_flash

    #   respond_to do |format|
    #     format.html # if you have an HTML view for this action
    #     format.json do
    #       render json: @posts.as_json()
    #     end
    #   end
    # end

    def activity
      @posts = Thredded::PostsPageView.new(
        thredded_current_user,
        preload_posts_for_moderation(moderatable_posts).order_newest_first
          .send(Kaminari.config.page_method_name, current_page)
          .preload_first_topic_post
      )
      maybe_set_last_moderated_record_flash

      respond_to do |format|
        format.html # if you have an HTML view for this action
        format.json do
          render json: {
            posts: @posts.map { |post_view| # Assuming @posts supports Enumerable methods like map
              post = post_view.to_model # Access the actual Post model
              {
                id: post.id,
                content: post.content,
                created_at: post.created_at,
                updated_at: post.updated_at,
                is_topic_starter: post.id == post.postable.first_post.id,
                postable: post.postable ? {
                  id: post.postable.id,
                  title: post.postable.title,
                  slug: post.postable.slug,
                  url: "/channel/#{post.postable.messageboard.slug}/#{post.postable.slug}"
                } : nil,
                user: {
                  id: post.user.id,
                  name: post.user.full_name, # Assuming user has a name method or attribute
                  avatar_url: post.user.avatar_url
                }
              }
            }
          }
        end
      end
    end

    def moderate_post
      moderation_state = params[:moderation_state].to_s
      return head(:bad_request) unless Thredded::Post.moderation_states.include?(moderation_state)
      post = moderatable_posts.find(params[:id].to_s)
      if post.moderation_state != moderation_state
        flash[:last_moderated_record_id] = Thredded::ModeratePost.run!(
          post: post,
          moderation_state: moderation_state,
          moderator: thredded_current_user,
        ).id
      else
        flash[:alert] = "Post was already #{moderation_state}:"
        flash[:last_moderated_record_id] =
          Thredded::PostModerationRecord.order_newest_first.find_by(post_id: post.id)&.id
      end
      redirect_back fallback_location: pending_moderation_path
    end

    # def users
    #   @users = Thredded.user_class
    #     .eager_load(:thredded_user_detail)
    #     .merge(
    #       Thredded::UserDetail.order(
    #         Arel.sql('COALESCE(thredded_user_details.moderation_state, 0) ASC,'\
    #                  'thredded_user_details.moderation_state_changed_at DESC')
    #       )
    #     )
    #   @query = params[:q].to_s
    #   @users = DbTextSearch::CaseInsensitive.new(@users, Thredded.user_name_column).prefix(@query) if @query.present?
    #   @users = @users.send(Kaminari.config.page_method_name, current_page)
    # end

    def users
      @users = Thredded.user_class
        .eager_load(:thredded_user_detail)
        .merge(
          Thredded::UserDetail.order(
            Arel.sql('COALESCE(thredded_user_details.moderation_state, 0) ASC, ' +
                     'thredded_user_details.moderation_state_changed_at DESC')
          )
        )
      @query = params[:q].to_s
      @users = DbTextSearch::CaseInsensitive.new(@users, Thredded.user_name_column).prefix(@query) if @query.present?
      @users = @users.send(Kaminari.config.page_method_name, current_page)

      respond_to do |format|
        format.html # Standard HTML response (possibly renders a view)
        format.json {
          render json: @users.as_json(include: {
                                        thredded_user_detail: {
                                          only: [:moderation_state, :moderation_state_changed_at]
                                        }
                                      }, only: [:first_name, :last_name, :job_title, :avatar_url, :id]) # Customize these attributes as necessary
        }
      end
    end

    # def user
    #   @user = Thredded.user_class.find(params[:id])
    #   # Do not apply policy_scope here, as we want to show blocked posts as well.
    #   posts_scope = @user.thredded_posts
    #     .where(messageboard_id: policy_scope(Messageboard.all).pluck(:id))
    #     .order_newest_first
    #     .includes(:postable)
    #     .send(Kaminari.config.page_method_name, current_page)
    #   @posts = Thredded::PostsPageView.new(thredded_current_user, posts_scope)
    # end

    # def user
    #   @user = Thredded.user_class.find(params[:id])
    #   posts_scope = @user.thredded_posts
    #     .where(messageboard_id: policy_scope(Messageboard.all).pluck(:id))
    #     .order_newest_first
    #     .includes(:postable)
    #     .send(Kaminari.config.page_method_name, current_page)
    #   @posts = Thredded::PostsPageView.new(thredded_current_user, posts_scope)

    #   respond_to do |format|
    #     format.html # Render a view if necessary
    #     format.json {
    #       render json: {
    #         user: {
    #           id: @user.id,
    #           email: @user.email,
    #           moderation: @user.thredded_user_detail
    #         },
    #         posts: @posts.to_a.map { |post_view|
    #           post = post_view.to_model  # Access the actual Post object from PostView
    #           {
    #             id: post.id,
    #             content: post.content,
    #             postable: post.postable ? { id: post.postable.id, title: post.postable.title, slug: post.postable.slug } : nil,
    #             user: {
    #               first_name: post.user.first_name,
    #               last_name: post.user.last_name,
    #               job_title: post.user.job_title,
    #               avatar_url: post.user.avatar_url
    #             }
    #           }
    #         }
    #       }
    #     }
    #   end
    # end

    def user
      @user = Thredded.user_class.find(params[:id])
      posts_scope = @user.thredded_posts
        .where(messageboard_id: policy_scope(Messageboard.all).pluck(:id))
        .order_newest_first
        .includes(:postable, :user) # Make sure to include associated users and postable
        .send(Kaminari.config.page_method_name, current_page)
      @posts = Thredded::PostsPageView.new(thredded_current_user, posts_scope)

      respond_to do |format|
        format.html # Render a view if necessary
        format.json {
          render json: {

            moderation: @user.thredded_user_detail,
            posts: @posts.to_a.map { |post_view|
                     post = post_view.to_model # Access the actual Post object from PostView
                     {
                       id: post.id,
                       is_topic_starter: post.id == post.postable.first_post.id, # Check if it's a starter post
                       postable: post.postable ? {
                         id: post.postable.id,
                         title: post.postable.title,
                         slug: post.postable.slug,
                         url: "/channel/#{post.postable.messageboard.slug}/#{post.postable.slug}"
                       } : nil,
                     }
                   }
          }
        }
      end
    end

    # def moderate_user
    #   return head(:bad_request) unless Thredded::UserDetail.moderation_states.include?(params[:moderation_state])
    #   user = Thredded.user_class.find(params[:id])
    #   user.thredded_user_detail.update!(moderation_state: params[:moderation_state])
    #   redirect_back fallback_location: user_moderation_path(user.id)
    # end

    def moderate_user
      return head(:bad_request) unless Thredded::UserDetail.moderation_states.include?(params[:moderation_state])

      user = Thredded.user_class.find(params[:id])

      if user.thredded_user_detail.update(moderation_state: params[:moderation_state])
        respond_to do |format|
          format.html { redirect_back fallback_location: user_moderation_path(user.id) }
          format.json {
            render json: { status: 'success', message: 'Moderation state updated successfully.',
                           moderation: user.thredded_user_detail }
          }
        end
      else
        respond_to do |format|
          format.html {
            redirect_back fallback_location: user_moderation_path(user.id), alert: 'Failed to update moderation state.'
          }
          format.json {
            render json: { status: 'error', message: 'Failed to update moderation state.' },
                   status: :unprocessable_entity
          }
        end
      end
    end

    private

    def maybe_set_last_moderated_record_flash
      return unless flash[:last_moderated_record_id]
      @last_moderated_record = accessible_post_moderation_records.find(flash[:last_moderated_record_id].to_s)
    end

    def moderatable_posts
      if moderatable_messageboards == Thredded::Messageboard.all
        Thredded::Post.all
      else
        Thredded::Post.where(messageboard_id: moderatable_messageboards)
      end
    end

    def accessible_post_moderation_records
      if moderatable_messageboards == Thredded::Messageboard.all
        Thredded::PostModerationRecord.all
      else
        Thredded::PostModerationRecord.where(messageboard_id: moderatable_messageboards)
      end
    end

    def moderatable_messageboards
      @moderatable_messageboards ||= thredded_current_user.thredded_can_moderate_messageboards
    end

    def current_page
      (params[:page] || 1).to_i
    end

    def preload_posts_for_moderation(posts)
      posts.includes(:user, :messageboard, :postable)
    end
  end
end
