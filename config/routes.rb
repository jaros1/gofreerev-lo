GofreerevFb::Application.routes.draw do

  filter :locale

  get "about/index"
  get "about/unsubscribe"
  get "about/ad1"
  get 'cookie/decline_cookies'
  get "flickr/index"
  get "linkedin/index"
  get '/auth/:provider/callback', :to => 'auth#create'
  post '/auth/:provider/callback', :to => 'auth#create'
  get '/auth/failure' do
    flash = Flash.new
    flash.message = params[:message] # if using sinatra-flash or rack-flash
    flash.save!
    session[:flash_id] = flash.id
    redirect '/auth'
  end
  get '/auth', :to => 'auth#index'
  get '/auth/index'

  get 'util/new_messages_count'
  post 'util/missing_api_picture_urls'
  post 'util/like_gift'
  post 'util/unlike_gift'
  post 'util/follow_gift'
  post 'util/unfollow_gift'
  post 'util/hide_gift'
  post 'util/delete_gift'
  post 'util/cancel_new_deal'
  post 'util/accept_new_deal'
  post 'util/reject_new_deal'
  post 'util/do_tasks'
  get 'util/currencies'
  post 'util/post_on_wall_yn'
  post 'util/grant_write'
  post 'util/hide_grant_write'
  delete 'auth/destroy'
  post 'util/share_accounts'
  post 'util/share_gift'
  post 'util/open_graph'

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  root :to => 'auth#index', :via => :all, :constraints => RoleConstraint.new(:empty, :not_logged_in), :as => 'root1'
  root :to => 'gifts#index', :via => :all, :constraints => RoleConstraint.new(:empty, :logged_in), :as => 'root2'
  root :to => 'facebook#create', :via => :all, :constraints => RoleConstraint.new(:fb_locale, :signed_request), :as => 'root3'
  root :to => 'auth#index', :via => :all, :constraints => RoleConstraint.new(:not_logged_in), :as => 'root4'
  root :to => 'gifts#index', :via => :all, :constraints => RoleConstraint.new(:logged_in), :as => 'root5'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  scope "(:locale)" do
    resources :gifts, :users, :inbox, :comments, :facebook
  end

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end
  
  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
