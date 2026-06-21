module Api
  module V1
    class CommunityController < BaseController
      PER_PAGE = 20

      # GET /api/v1/community/feed
      def feed
        filter = params[:filter].presence_in(%w[all friends similar]) || "all"
        page   = [params[:page].to_i, 1].max

        scope = community_posts_scope(filter)
          .includes(user: :public_profile)
          .limit(PER_PAGE)
          .offset((page - 1) * PER_PAGE)

        reaction_post_ids = current_user.community_reactions.pluck(:community_post_id).to_set

        posts = scope.map { |post| serialize_post(post, reaction_post_ids) }
        render json: { posts: posts }
      end

      # GET /api/v1/community/profile
      def profile
        pub = current_user.public_profile || current_user.create_public_profile
        render json: serialize_community_profile(pub)
      end

      # PATCH /api/v1/community/profile
      def update_profile
        pub = current_user.public_profile || current_user.create_public_profile
        permitted = params.permit(
          :display_name, :public_bio, :avatar_visible,
          :show_workout_count, :show_streak, :show_badges,
          :show_points, :show_progress_photos
        )
        if pub.update(permitted)
          # Sync community_enabled based on profile visibility
          current_user.update_column(:community_enabled, current_user.profile_visibility != "private")
          render json: serialize_community_profile(pub)
        else
          render json: { errors: pub.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/community/posts/:id/reactions
      def create_reaction
        post = CommunityPost.find(params[:id])
        reaction = current_user.community_reactions.find_or_initialize_by(community_post_id: post.id)
        reaction.reaction_type = params[:reaction_type].presence_in(CommunityReaction::REACTION_TYPES) || "congrats"
        if reaction.save
          render json: { reaction_count: post.community_reactions.count, reacted: true }
        else
          render json: { errors: reaction.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/community/posts/:id/reactions
      def destroy_reaction
        post = CommunityPost.find(params[:id])
        reaction = current_user.community_reactions.find_by(community_post_id: post.id)
        reaction&.destroy
        render json: { reaction_count: post.community_reactions.count, reacted: false }
      end

      # POST /api/v1/community/posts/:id/comments
      def create_comment
        post = CommunityPost.find(params[:id])
        comment = post.community_comments.build(user: current_user, body: params[:body].to_s.strip)
        if comment.save
          render json: serialize_comment(comment), status: :created
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/community/comments/:id
      def destroy_comment
        comment = current_user.community_comments.find(params[:id])
        comment.destroy
        render json: { ok: true }
      end

      # POST /api/v1/community/congrats/:id  (legacy — delegates to create_reaction)
      def congrats
        post = CommunityPost.find_by(id: params[:id])
        if post
          current_user.community_reactions.find_or_create_by(
            community_post_id: post.id,
            reaction_type: "congrats"
          )
          render json: { ok: true, reaction_count: post.community_reactions.count }
        else
          # Fallback: track as user event (old behavior for session-based congrats)
          UserEventService.track(
            user: current_user,
            event: :community_congrats,
            metadata: { target_id: params[:id] }
          )
          render json: { ok: true }
        end
      end

      private

      def community_posts_scope(filter)
        base = CommunityPost.for_feed.where.not(user_id: current_user.id)

        case filter
        when "friends"
          friend_ids = current_user.clients.pluck(:id) + current_user.personal_trainers.pluck(:id)
          base.where(user_id: friend_ids)
        when "similar"
          base.where(user_id: similar_user_ids)
        else
          base
        end
      end

      def similar_user_ids
        return [] unless current_user.health_profile
        goal  = current_user.health_profile.goal
        level = current_user.health_profile.fitness_level
        User.joins(:health_profile)
          .where(health_profiles: { goal: goal, fitness_level: level })
          .where.not(id: current_user.id)
          .where(community_enabled: true)
          .pluck(:id)
      end

      def serialize_post(post, reaction_post_ids)
        user = post.user
        pub  = user.public_profile
        return nil unless pub

        display_name = pub.display_name.presence || user.name.split.first
        hue = hue_from_name(display_name)

        {
          id:             post.id,
          name:           display_name,
          hue:            hue,
          avatar_url:     pub.avatar_visible ? avatar_url_for(user) : nil,
          time:           time_ago(post.created_at),
          type:           map_post_type(post.post_type),
          title:          post.title,
          highlight:      build_highlight(post.metadata),
          streak_days:    post.post_type == "streak_achieved" ? streak_dots_from_metadata(post.metadata) : nil,
          reaction_count: post.community_reactions.size,
          reacted:        reaction_post_ids.include?(post.id),
          comment_count:  post.community_comments.size,
        }
      end

      def serialize_community_profile(pub)
        {
          display_name:         pub.display_name,
          public_bio:           pub.public_bio,
          avatar_visible:       pub.avatar_visible,
          show_workout_count:   pub.show_workout_count,
          show_streak:          pub.show_streak,
          show_badges:          pub.show_badges,
          show_points:          pub.show_points,
          show_progress_photos: pub.show_progress_photos,
          profile_visibility:   pub.user.profile_visibility,
          community_enabled:    pub.user.community_enabled,
        }
      end

      def serialize_comment(comment)
        {
          id:         comment.id,
          body:       comment.body,
          user_name:  comment.user.public_profile&.display_name.presence || comment.user.name.split.first,
          created_at: comment.created_at.iso8601,
        }
      end

      def map_post_type(raw)
        case raw
        when "workout_completed"   then "workout"
        when "streak_achieved"     then "streak"
        when "achievement_unlocked" then "achievement"
        when "progress_update"     then "evolution"
        else "workout"
        end
      end

      def build_highlight(meta)
        parts = []
        parts << "#{meta['duration_minutes']} min"  if meta["duration_minutes"].present?
        parts << "#{meta['calories_estimated']} kcal" if meta["calories_estimated"].present?
        parts.join(" · ").presence
      end

      def streak_dots_from_metadata(meta)
        # Returns last 7 days attendance — stored as streak count in metadata
        streak = meta["streak"].to_i
        dots = Array.new(7, 0)
        [streak, 7].min.times { |i| dots[6 - i] = 1 }
        dots
      end

      def time_ago(time)
        diff = (Time.current - time).to_i
        if diff < 3600
          "#{diff / 60}min atrás"
        elsif diff < 86_400
          "#{diff / 3600}h atrás"
        else
          "#{diff / 86_400}d atrás"
        end
      end

      def hue_from_name(name)
        name.chars.reduce(0) { |h, c| (h * 31 + c.ord) % 360 }
      end

      def avatar_url_for(user)
        return nil unless user.avatar.attached?
        Rails.application.routes.url_helpers.rails_blob_url(user.avatar, only_path: true)
      rescue
        nil
      end
    end
  end
end
