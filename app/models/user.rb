class User < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  validates :firebase_uid, presence: true, uniqueness: true
  validates :email, presence: true

  # Firebase の ID トークンから検証済みクレームを受け取り、ユーザーを find or create する
  # @param claims [Hash] FirebaseAuthVerifier#verify の戻り値（sub, email, name 等を含む）
  # @return [User]
  def self.from_firebase_claims(claims)
    sub = claims["sub"] || claims[:sub]
    raise ArgumentError, "missing sub claim" if sub.blank?

    user = find_or_initialize_by(firebase_uid: sub)
    user.email = claims["email"] || claims[:email]
    user.display_name = claims["name"] || claims[:name] || user.email&.split("@")&.first
    user.notification_enabled = true if user.new_record?
    user.save!
    user
  end
end
