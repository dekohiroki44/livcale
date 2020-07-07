class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  validates :name, presence: true, length: { maximum: 50 }
  validates :profile, length: { maximum: 200 }
  validates_acceptance_of :agreement, allow_nil: false, on: :create
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.freeze
  validates :email, format: { with: VALID_EMAIL_REGEX }
  has_many :tickets, dependent: :destroy
  has_one_attached :image
  before_create :default_image
  has_many :active_relationships, class_name: "Relationship",
                                  foreign_key: "follower_id",
                                  dependent: :destroy
  has_many :passive_relationships, class_name: "Relationship",
                                   foreign_key: "followed_id",
                                   dependent: :destroy
  has_many :following, through: :active_relationships, source: :followed
  has_many :followers, through: :passive_relationships, source: :follower
  has_many :likes, dependent: :destroy
  has_many :comments
  has_many :active_notifications, class_name: 'Notification',
                                  foreign_key: 'visitor_id',
                                  dependent: :destroy
  has_many :passive_notifications, class_name: 'Notification',
                                   foreign_key: 'visited_id',
                                   dependent: :destroy

  after_update do
    get_spotify_info if saved_change_to_recommend?
  end

  def feed
    following_ids = "SELECT followed_id FROM relationships
                     WHERE follower_id = :user_id"
    Ticket.where("(user_id IN (#{following_ids}) AND public = :public) OR user_id = :user_id", public: true, user_id: id)
  end

  def follow(other_user)
    following << other_user
  end

  def unfollow(other_user)
    active_relationships.find_by(followed_id: other_user.id).destroy
  end

  def following?(other_user)
    following.include?(other_user)
  end

  def create_notification_follow!(current_user)
    temp = Notification.
      where(["visitor_id = ? and visited_id = ? and action = ? ", current_user.id, id, 'follow'])
    if temp.blank?
      notification = current_user.active_notifications.new(
        visited_id: id,
        action: 'follow'
      )
      notification.save if notification.valid?
    end
  end

  def most_places(count)
    tickets.
      pluck(:place).
      join(",").
      gsub(" ", "").
      downcase.split(",").
      group_by(&:itself).
      sort_by { |_, v| -v.size }.
      map(&:first).
      take(count).
      join(", ")
  end

  def most_artists(count)
    tickets.
      pluck(:performer).
      join(",").
      gsub(", ", ",").
      downcase.
      split(",").
      group_by(&:itself).
      sort_by { |_, v| -v.size }.
      map(&:first).
      take(count).
      join(", ")
  end

  def suggests(count)
    user_ids = Ticket.
      where('UPPER(performer) LIKE ?', "%#{most_artists(1)}%".upcase).
      where.not(user_id: id).
      pluck(:user_id).
      uniq
    array = []
    user_ids.each do |user_id|
      array << User.find(user_id).tickets.done.take(5).pluck(:performer).join(",")
    end
    recently_performers = array.join(",").gsub(", ", ",").downcase.split(",")
    recently_performers.delete(most_artists(1))
    recently_performers.
      group_by(&:itself).
      sort_by { |_, v| -v.size }.
      map(&:first).
      take(count).
      join(", ")
  end

  def self.search(word, date)
    if word.present?
      User.where("upper(name) LIKE ? OR upper(profile) LIKE ?", "%#{word}%".upcase, "%#{word}%".upcase)
    elsif word.blank? && date.present?
      user_ids = Ticket.where(date: date..date + 1.day).release.pluck(:user_id)
      User.where(id: user_ids)
    elsif word.blank? && date.blank?
      User.all
    end
  end

  def spotify
    if recommend.present? && authenticate_token.present?
      client = HTTPClient.new
      url = 'https://api.spotify.com/v1/search'
      query = { "q": recommend, "type": "artist", "market": "JP" }
      header = { "Authorization": "Bearer #{authenticate_token}", "Accept-Language": "ja;q=1" }
      response_ja = client.get(url, query, header)
      spotify_artist_ja = JSON.parse(response_ja.body)
      header = { "Authorization": "Bearer #{authenticate_token}" }
      response_en = client.get(url, query, header)
      spotify_artist_en = JSON.parse(response_en.body)

      numbers = [0, 1, 2, 3, 4, 5]
      spotify_id = ""
      image_url = ""
      if response_en.status == 200
        numbers.each do |number|
          if spotify_artist_en["artists"]["items"][number].present? &&
            spotify_artist_en["artists"]["items"][number]["name"].downcase == recommend.downcase
            spotify_id = spotify_artist_en["artists"]["items"][number]["id"]
            if spotify_artist_en["artists"]["items"][number]["images"].present?
              image_url = spotify_artist_en["artists"]["items"][number]["images"][1]["url"]
            end
            break
          end
        end
      end

      if response_ja.status == 200
        numbers.each do |number|
          if spotify_artist_ja["artists"]["items"][number].present? &&
            spotify_artist_ja["artists"]["items"][number]["name"].downcase == recommend.downcase
            spotify_id = spotify_artist_ja["artists"]["items"][number]["id"]
            if spotify_artist_ja["artists"]["items"][number]["images"].present?
              image_url = spotify_artist_ja["artists"]["items"][number]["images"][1]["url"]
            end
            break
          end
        end
      end

      if spotify_id.present?
        url = "https://api.spotify.com/v1/artists/#{spotify_id}/top-tracks"
        query = { "market": "JP", "limit": 1 }
        response = client.get(url, query, header)

        if response.status == 200
          top_tracks = JSON.parse(response.body)
          track_url = top_tracks["tracks"].sample["preview_url"] if top_tracks["tracks"].present?
          return image_url, track_url
        else
          return image_url, nil
        end
      else
        [nil, nil]
      end
    end
    [nil, nil]
  end

  private

  def default_image
    if !image.attached?
      file = File.open(Rails.root.join('public', 'images', 'no_picture.jpg'))
      image.attach(io: file, filename: 'no_picture.jpg', content_type: 'image/jpg')
    end
  end

  def authenticate_token
    url = "https://accounts.spotify.com/api/token"
    query = { "grant_type": "client_credentials" }
    key = Rails.application.credentials.spotify[:client_base64]
    header = { "Authorization": "Basic #{key}" }
    client = HTTPClient.new
    response = client.post(url, query, header)
    if response.status == 200
      auth_params = JSON.parse(response.body)
      auth_params["access_token"]
    end
  end

  def get_spotify_info
    update_attributes(recommend_image: spotify[0], recommend_track: spotify[1])
  end
end
