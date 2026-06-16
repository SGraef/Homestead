# frozen_string_literal: true
# typed: false

require "rails_helper"

RSpec.describe "Todo notifications, assignment & follow" do
  let(:admin)      { create(:user) }
  let!(:household) { create(:household, admin: admin) }
  let(:member) do
    u = create(:user)
    Membership.create!(user: u, household: household, role: "member")
    u
  end

  before { login_via_post(admin) }

  describe "assignment" do
    it "notifies and auto-follows the assignee" do
      todo = create(:todo, household: household, creator: admin)

      expect { patch todo_path(todo), params: { todo: { assignee_id: member.id } } }
        .to change { member.notifications.where(kind: "assigned").count }.by(1)
      expect(todo.reload.followed_by?(member)).to be(true)
    end

    it "does not notify on self-assignment" do
      todo = create(:todo, household: household, creator: admin)
      expect { patch todo_path(todo), params: { todo: { assignee_id: admin.id } } }
        .not_to change(Notification, :count)
    end

    it "rejects an assignee who is not a household member" do
      stranger = create(:user) # no membership
      todo = create(:todo, household: household)
      patch todo_path(todo), params: { todo: { assignee_id: stranger.id } }
      expect(todo.reload.assignee_id).to be_nil
    end
  end

  describe "status change notifies followers (except actor)" do
    it "sends one to a follower and none to the acting user" do
      todo = create(:todo, household: household, status: "open")
      todo.follow!(member)
      todo.follow!(admin)

      expect { post transition_todo_path(todo, to: "in_progress") }
        .to change { member.notifications.count }.by(1)
        .and change { admin.notifications.count }.by(0)
    end
  end

  describe "comment notifies followers (except commenter)" do
    it "sends one to a follower and none to the commenter" do
      todo = create(:todo, household: household)
      todo.follow!(member)
      todo.follow!(admin)

      expect { post todo_comments_path(todo), params: { todo_comment: { body: "Done soon" } } }
        .to change { member.notifications.where(kind: "comment_added").count }.by(1)
        .and change { admin.notifications.count }.by(0)
    end
  end

  describe "follow / unfollow" do
    it "follows then unfollows" do
      todo = create(:todo, household: household)
      post follow_todo_path(todo)
      expect(todo.reload.followed_by?(admin)).to be(true)
      delete unfollow_todo_path(todo)
      expect(todo.reload.followed_by?(admin)).to be(false)
    end
  end

  describe "notification bell" do
    it "lists, reads one (deep-link), and marks all read" do
      n = create(:notification, household: household, user: admin, url: "/todos/1")

      get notifications_path
      expect(response).to have_http_status(:ok)

      post read_notification_path(n)
      expect(n.reload).to be_read
      expect(response).to redirect_to("/todos/1")

      create(:notification, household: household, user: admin)
      post read_all_notifications_path
      expect(admin.notifications.unread.count).to eq(0)
    end

    it "only shows the current user's own notifications" do
      mine   = create(:notification, household: household, user: admin,  title: "Mine alert")
      theirs = create(:notification, household: household, user: member, title: "Their alert")

      get notifications_path
      expect(response.body).to include("Mine alert")
      expect(response.body).not_to include("Their alert")

      post read_notification_path(theirs)
      expect(response).to have_http_status(:not_found)
      expect(theirs.reload).not_to be_read
    end
  end
end
