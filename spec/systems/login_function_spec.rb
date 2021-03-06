require 'rails_helper'

describe 'login_function', type: :system do
  before do
    visit new_user_session_path
  end

  context 'when make a wrong input' do
    before do
      fill_in 'Eメール', with: ''
      fill_in 'パスワード', with: ''
      click_button 'ログイン'
    end

    it 'shows flash messages' do
      expect(page).to have_selector('#alert', text: 'Eメールまたはパスワードが違います。')
      expect(page).to have_current_path new_user_session_path
    end

    it 'does not show flash messages on next view' do
      within '#sidebar-wrapper' do
        click_link 'Ticket Rec'
      end
      expect(page).not_to have_selector('#alert', text: 'Eメールまたはパスワードが違います。')
    end
  end

  context 'when make a correct input' do
    let(:user) { create(:user) }

    before do
      fill_in 'Eメール', with: user.email
      fill_in 'パスワード', with: user.password
      click_button 'ログイン'
    end

    it 'shows correct links' do
      expect(page).to have_link 'マイページ', href: user_path(user)
      expect(page).to have_link '皆んなのチケット', href: tickets_path
      expect(page).to have_link '書き込む', href: new_ticket_path
      expect(page).to have_link '通知', href: notifications_path
      expect(page).to have_link 'Ticket Recについて', href: about_path
      expect(page).to have_link 'ログアウト', href: destroy_user_session_path
      expect(page).not_to have_link '新規登録', href: new_user_registration_path
      expect(page).not_to have_link 'ログイン', href: new_user_session_path
    end

    it 'has logout function' do
      within '#sidebar-wrapper' do
        click_link 'ログアウト'
      end
      expect(current_path).to eq root_path
      expect(page).to have_link '新規登録', href: new_user_registration_path
      expect(page).to have_link 'ログイン', href: new_user_session_path
      expect(page).not_to have_link 'マイページ', href: user_path(user)
      expect(page).not_to have_link '皆んなのチケット', href: tickets_path
      expect(page).not_to have_link '書き込む', href: new_ticket_path
      expect(page).not_to have_link '通知', href: notifications_path
      expect(page).not_to have_link 'Ticket Recについて', href: about_path
      expect(page).not_to have_link 'ログアウト', href: destroy_user_session_path
    end
  end

  context 'when cllick guest login' do
    before do
      within '#sidebar-wrapper' do
        click_link 'ゲストログイン（閲覧用）'
      end
    end

    it 'creates guest user' do
      expect(User.count).to eq 1
      expect(User.last.name).to eq 'ゲストユーザー'
    end

    it 'shows correct links' do
      expect(page).to have_link 'マイページ', href: user_path(User.last)
      expect(page).to have_link '皆んなのチケット', href: tickets_path
      expect(page).to have_link '書き込む', href: new_ticket_path
      expect(page).to have_link '通知', href: notifications_path
      expect(page).to have_link 'Ticket Recについて', href: about_path
      expect(page).to have_link 'ログアウト', href: destroy_user_session_path
      expect(page).not_to have_link '新規登録', href: new_user_registration_path
      expect(page).not_to have_link 'ログイン', href: new_user_session_path
    end

    it 'has logout function' do
      within '#sidebar-wrapper' do
        click_link 'ログアウト'
      end
      expect(current_path).to eq root_path
      expect(page).to have_link '新規登録', href: new_user_registration_path
      expect(page).to have_link 'ログイン', href: new_user_session_path
      expect(page).not_to have_link 'マイページ', href: user_path(User.last)
      expect(page).not_to have_link '皆んなのチケット', href: tickets_path
      expect(page).not_to have_link '書き込む', href: new_ticket_path
      expect(page).not_to have_link '通知', href: notifications_path
      expect(page).not_to have_link 'Ticket Recについて', href: about_path
      expect(page).not_to have_link 'ログアウト', href: destroy_user_session_path
    end
  end
end
