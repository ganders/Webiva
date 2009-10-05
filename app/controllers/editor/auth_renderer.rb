# Copyright (C) 2009 Pascal Rettig.

class Editor::AuthRenderer < ParagraphRenderer

  features '/editor/auth_feature'
  
  paragraph :login
  paragraph :enter_vip
  paragraph :register
  paragraph :edit_account
  paragraph :missing_password
  paragraph :email_list
  paragraph :splash

  def login
    opts = paragraph_options(:login)

   
    data = {}
    if myself.id
      data[:user] = myself
    end
    
    if params[:cms_logout]
       paragraph_action(myself.action('/editor/auth/logout'))
       process_logout
       redirect_paragraph :page
       return
    elsif request.post? && !editor?
      if(params[:cms_login] && params[:cms_login][:password] && (params[:cms_login][:login] || params[:cms_login][:username]))
        if opts.login_type == 'email' || opts.login_type == 'both'
          user = EndUser.login_by_email(params[:cms_login][:login],params[:cms_login][:password])
          user ||= EndUser.login_by_username(params[:cms_login][:login],params[:cms_login][:password]) unless user || opts.login_type == 'email'
        else
          user = EndUser.login_by_username(params[:cms_login][:username],params[:cms_login][:password])
        end
        
        if user
          process_login(user,params[:cms_login][:remember].to_s == '1')
          paragraph_action(myself.action('/editor/auth/login'))
         
          if opts.forward_login == 'yes' && session[:lock_lockout]
              lock_logout = session[:lock_lockout]
              session[:lock_lockout] = nil
              redirect_paragraph lock_logout
              return
          elsif opts.success_page
            nd = SiteNode.find_by_id(opts.success_page)
            if nd
              redirect_paragraph nd.node_path
              return
            end
          end
          redirect_paragraph :page
          return
        else
          if(opts.failure_page.to_i > 0)
              flash[:auth_user_login_error] = true
              redirect_paragraph :site_node => opts.failure_page.to_i
              return
          else
            data[:error] = true
          end
        end
      end
    end
    data[:error] = true if flash[:auth_user_login_error]
    data[:type] = opts.login_type
    
    render_paragraph :text => login_feature(get_feature('login'),data)
  end
  
  
  def enter_vip
    opts = paragraph.data
  
    data = { :failure => false, :registered => myself.registered? }
    
    if !editor? &&  request.post? && params[:vip] && !params[:vip][:number].blank?
      vip_number = params[:vip][:number]
      
      user = EndUser.find_by_vip_number(vip_number)
      if user
        # Must be VIP # for unregistered user, or paragraph must allow it
        if !user.registered? || opts[:login_even_if_registered]
          
          session[:user_id] = user.id
          session[:user_model] = user.class.to_s
          reset_myself
          
          
          paragraph_action('Enter VIP, Success',vip_number)
          if !editor? && paragraph.update_action_count > 0
            paragraph.run_triggered_actions(myself,'success',myself)
          end
          
          
          user.update_attribute(:user_level, 2) if user.user_level < 2
          
          if !opts[:add_tags].to_s.empty?
            user.tag_names_add(opts[:add_tags])
          end
          
          @nd = SiteNode.find_by_id(opts[:already_registered_page]) if user.registered? && opts[:already_registered_page]
          
          @nd = SiteNode.find_by_id(opts[:success_page]) unless @nd
          if @nd 
            redirect_paragraph @nd.node_path
            return 
	  end
        else
          if !editor? && paragraph.update_action_count > 0
            paragraph.run_triggered_actions(myself,'repeat',myself)
          end
          paragraph_action('Enter VIP, Repeat',vip_number)
          data[:registered] = true
        end
      else
        if !editor? && paragraph.update_action_count > 0
          paragraph.run_triggered_actions(myself,'failure',EndUser.new(:vip_number => vip_number))
        end
         paragraph_action('Enter VIP, Fail',vip_number)
        data[:failure] = true
      end
    end
    
    render_paragraph :text => enter_vip_feature(data)  
  end
  
  
  
  
  def register
    opts = Editor::AuthController::RegisterOptions.new(paragraph.data)
    
    @optional_fields = %w{gender membership_id first_name last_name username}
    
    if ( myself.registered? || myself.user_class_id == opts.user_class_id) && !editor? 
      if opts.already_registered_redirect.to_i > 0
        nd = SiteNode.find_by_id(opts.already_registered_redirect)
        if nd 
          redirect_paragraph nd.node_path if nd
          return 
	  end
      else
        render_paragraph :text => 'Already registered'.t
        return
      end
      
    end
    

    if opts.content_publication.to_i > 0 && (@publication = ContentPublication.find_by_id(opts.content_publication.to_i))
        

        require_js('prototype')
        require_js('overlib/overlib')
        require_js('user_application')

    
        @entry = @publication.content_model.content_model.new(params['entry_' + @publication.id.to_s])

    end

    
    @user = myself
    @user = EndUser.new unless myself.is_a?(EndUser)
    @address = @user.address ? @user.address : @user.build_address(:address_name => 'Default Address'.t )
    @work_address = @user.work_address ? @user.work_address : @user.build_work_address(:address_name => 'Default Work Address'.t )

    if opts.clear_info.to_s == 'y'
      if @user.id
        %w(email first_name last_name gender ).each { |fld| @user.send(fld + "=",'') }
        adr_fields = %w(company phone fax address city state zip country)
        adr_fields.each { |fld| @address.send(fld + "=",'') }
        adr_fields.each { |fld| @work_address.send(fld + "=",'') }
      end
    end
    
    if !editor? && request.post? && params[:user]
    
      # See we already have an unregistered user with this email
      @user = EndUser.find_visited_target(params[:user][:email])
      
      if @user.registered?
        # If not, we need to create a new user
        @user = EndUser.new(:source => 'website')
      end
      @user.attributes = params[:user]

      if !@user.id || opts.modify_profile == 'modify'
        @user.user_class_id = opts.user_class_id
      end
      @user.language = session[:cms_language]
      if opts.registration_type == 'login'
        @user.registered = true
        @user.user_level = 3 unless @user.user_level > 3
      else
        @user.user_level = 2 unless @user.user_level > 2 
      end
      
      
      all_valid = true
      if opts.address != 'off'

        @address.attributes = params[:address]
        @address.country = opts.country unless opts.country.blank?
        @address.validate_registration(:home,opts.address == 'required',opts.address_type )
        all_valid = false unless @address.errors.empty?
      end
      
      if opts.work_address != 'off'
        @work_address.attributes = params[:work_address]
        @work_address.country = opts.country unless opts.country.blank?
        @work_address.validate_registration(:work,opts.work_address == 'required',opts.address_type )
        @work_address.errors.add(:fax,'is missing') if opts.work_fax == 'required' && @work_address.fax.blank?
        all_valid = false unless @work_address.errors.empty?
      end
      

      if opts.content_publication.to_i > 0
          fill_entry(@publication,@entry,@user)
      
          all_valid = false unless @entry.valid?
      end

      
      @user.valid?

      if opts.site_policy != 'off'
        @user.errors.add(:site_policy,'must be accepted') if @user.site_policy != 'accept'
      end 
      
      if opts.membership_id != 'off'
        @user.errors.add(:membership_id,' must be entered') if opts.membership_id == 'required' && @user.membership_id.blank?
        
        if !@user.membership_id.blank?
          if !EndUser.find_by_email_and_membership_id(@user.email,@user.membership_id)
            @user.errors.add(:membership_id,' must match the number on file with your email address')
          end
        end
      end
      
      @user.errors.add(:captcha_key,'are incorrect') unless opts.captcha == 'off' || simple_captcha_valid?
  
      @user.validate_registration(opts.to_h)
      all_valid = false unless @user.errors.empty?
      
      if all_valid
        if opts.address != 'off'
          @address.save
          @user.address_id = @address.id
        end
        if opts.work_address != 'off'
      	  @work_address.save
	        @user.work_address_id = @work_address.id
        end

        # Set a source if we have one        
        if session[:user_referrer]
          @user.referrer = session[:user_referrer]
        end
        
        
        @user.save
        
        @user.tag_names_add(opts.add_tags) if !opts.add_tags.to_s.empty?
	      
        # add any session based tags on registration
        @user.tag_names_add(session[:user_tags]) if session[:user_tags]
        
        session[:user_tags] = nil
        session[:user_source] = nil
        
        if opts.include_subscriptions.is_a?(Array) && opts.include_subscriptions.length > 0
          update_subscriptions(@user,opts.include_subscriptions,params[:subscription])
        end 

        @address.update_attribute(:end_user_id,@user.id) if opts.address != 'off'
        @work_address.update_attribute(:end_user_id,@user.id) if opts.work_address != 'off'
        
	session[:user_id] = @user.id
	session[:user_model] = @user.class.to_s
	myself

        if opts.content_publication.to_i > 0
          fill_entry(@publication,@entry,@user)
          if @entry.save
            if @publication.update_action_count > 0
              @publication.run_triggered_actions(entry,'create',myself)
            end
          end
        end

        if paragraph.update_action_count > 0
          paragraph.run_triggered_actions(@user,'action',@user)
        end

        if opts.registration_template.to_i > 0 && @mail_template = MailTemplate.find_by_id(opts.registration_template.to_i)
            MailTemplateMailer.deliver_to_user(@user,@mail_template)

        end
	
      	paragraph_action('User Registration',@user.email)
	
        if session[:lock_lockout]
              lock_logout = session[:lock_lockout]
              session[:lock_lockout] = nil
              redirect_paragraph lock_logout
              return
        elsif opts.success_page.to_i > 0
          nd = SiteNode.find_by_id(opts.success_page)
          if nd 
            redirect_paragraph nd.node_path if nd
            return 
	       end
	      end
	      render_paragraph :text => 'Successful Registration'.t 
	      return
      end
    elsif !editor?
      if paragraph.view_action_count > 0
        paragraph.run_triggered_actions(@user,'view',@user)
      end
    end

    if opts.include_subscriptions.is_a?(Array) && opts.include_subscriptions.length > 0
      @subscriptions = UserSubscription.find(:all,:order => :name,:conditions => "id IN (#{opts.include_subscriptions.collect {|sub| DomainModel.connection.quote(sub) }.join(",")})")
    else
      @subscriptions = nil
    end
    
    display_options = opts.to_hash
    display_options[:vertical] = opts.form_display == 'vertical'
    
    render_paragraph :partial => '/editor/auth/register', 
                      :locals => { :user => @user, 
                                   :opts => display_options, 
                                   :fields => @optional_fields,
                                   :address => @address,
                                   :work_address => @work_address,
                                   :publication => @publication,
                                   :entry => @entry,
                                   :subscriptions => @subscriptions }
  end

  
  
  def edit_account
   opts = paragraph.data
    
    @optional_fields = %w{username gender first_name last_name}
    
    @user = myself
    @user = EndUser.new unless myself.is_a?(EndUser)
    @address = @user.address ? @user.address : @user.build_address(:address_name => 'Default Address'.t )
    @work_address = @user.work_address ? @user.work_address : @user.build_work_address(:address_name => 'Default Work Address'.t )

    if opts[:clear_info].to_s == 'y'
      if @user.id
        %w(email first_name last_name gender ).each { |fld| @user.send(fld + "=",'') }
        adr_fields = %w(company phone fax address city state zip country)
        adr_fields.each { |fld| @address.send(fld + "=",'') }
        adr_fields.each { |fld| @work_address.send(fld + "=",'') }
      end
    end
    
    if !editor? && request.post? && params[:user]
    
      # See we already have an unregistered user with this email
      @user = EndUser.find_visited_target(params[:user][:email])
      
      @user.attributes = params[:user]

      all_valid = true
      if opts[:address] != 'off'

        @address.attributes = params[:address]
        @address.country = opts[:country] unless opts[:country].blank?
        @address.validate_registration(:home,opts[:address] == 'required',opts[:address_type] )
        all_valid = false unless @address.errors.empty?
      end
      
      if opts[:work_address] != 'off'
        @work_address.attributes = params[:work_address]  
        @work_address.country = opts[:country] unless opts[:country].blank?
        @work_address.validate_registration(:work,opts[:work_address] == 'required',opts[:address_type] )
        all_valid = false unless @work_address.errors.empty?
      end
      

      if opts[:content_publication].to_i > 0
          fill_entry(@publication,@entry,@user)
      
          all_valid = false unless @entry.valid?
      end

      
      @user.valid?

      @user.validate_registration(opts)
      all_valid = false unless @user.errors.empty?
      
      if all_valid
        if opts[:address] != 'off'
          @address.save
          @user.address_id = @address.id
        end
        if opts[:work_address] != 'off'
	  @work_address.save
	  @user.work_address_id = @work_address.id
        end
        
        
        @user.save
        
	if !opts[:add_tags].to_s.empty?
	  @user.tag_names_add(opts[:add_tags])
	end
        
        if opts[:include_subscriptions].is_a?(Array) && opts[:include_subscriptions].length > 0
          update_subscriptions(@user,opts[:include_subscriptions],params[:subscription])
        end 

        @address.update_attribute(:end_user_id,@user.id) if opts[:address] != 'off'
        @work_address.update_attribute(:end_user_id,@user.id) if opts[:work_address] != 'off'

        if paragraph.update_action_count > 0
          paragraph.run_triggered_actions(@user,'action',@user)
        end

	paragraph_action('Edited Profile',@user.email)
	
        if opts[:success_page]
          nd = SiteNode.find_by_id(opts[:success_page])
          if nd 
            redirect_paragraph nd.node_path if nd
            return 
	 end
	end
	render_paragraph :text => 'Successfully Edited Profile'.t 
	return
      end
    end

    if opts[:include_subscriptions].is_a?(Array) && opts[:include_subscriptions].length > 0

      @subscriptions = UserSubscription.find(:all,:order => :name,:conditions => "id IN (#{opts[:include_subscriptions].collect {|sub| DomainModel.connection.quote(sub) }.join(",")})")
    else
      @subscriptions = nil
    end
    

    opts[:vertical] = opts[:form_display] == 'vertical'
    render_paragraph :partial => '/editor/auth/edit_account',
                      :locals => { :user => @user, 
                                   :opts => opts, 
                                   :fields => @optional_fields,
                                   :address => @address,
                                   :work_address => @work_address,
                                   :subscriptions => @subscriptions,
                                   :reset_password => flash['reset_password'] }
  end

# update users subscriptions
  def update_subscriptions(user,available_subscriptions,subscriptions)

    subscription_conditions = "user_subscription_id IN (#{available_subscriptions.collect {|sub| DomainModel.connection.quote(sub) }.join(",")})"
    user_subscription_conditions = "id IN (#{available_subscriptions.collect {|sub| DomainModel.connection.quote(sub) }.join(",")})"
    # Make sure we are updating subscriptions
    if subscriptions && subscriptions['0']

      user_subscriptions = user.user_subscription_entries.find(:all,:conditions => subscription_conditions).index_by(&:user_subscription_id)
      UserSubscription.find(:all,:conditions => user_subscription_conditions).each do |sub|
        # Now create an remove subscriptions as necessary
        if subscriptions[sub.id.to_s] && !user_subscriptions[sub.id]
           sub.subscribe_user(user)
        elsif !subscriptions[sub.id.to_s] && user_subscriptions[sub.id]
           user_subscriptions[sub.id].destroy
        end
      end
    end
  end
  

  
  
  def missing_password
    options = paragraph.data || {}
  
    @page_state = 'missing_password'
  
    if params[:verification]
      user = EndUser.login_by_verification(params[:verification])
      if user
          session[:user_id] = user.id
          session[:user_model] = user.class.to_s
          reset_myself
          
          response.data[:user].tag_names_add(session[:user_tags]) if session[:user_tags]
          session[:user_tags]
          
          flash['reset_password'] = true
          redirect_paragraph   SiteNode.get_node_path(options[:reset_password_page],'#')
          return
      else
        @invalid_verification = true
      end
    elsif params[:missing_password] && params[:missing_password][:email] 
      usr = nil
      EndUser.transaction do
        usr = EndUser.find_by_email(params[:missing_password][:email])
        if usr
          usr.update_verification_string!
        end        
      end
      email_template = MailTemplate.find(options[:email_template])
      
      if usr && email_template
        vars = { :verification => "http://" + request.domain(3) + site_node.node_path + "?verification=" + usr.verification_string }
	  
    	  MailTemplateMailer.deliver_to_user(usr,email_template,vars)
    	  flash['template_sent'] = true
    	  redirect_paragraph :page
    	  return
      end
    elsif flash['template_sent']
      @page_state = 'template_sent'
    end      
    
    data = { :invalid => @invalid_verification, :state => @page_state }
  
    render_paragraph :text =>  missing_password_feature(data)
  end


  
  
  def email_list
    @options = Editor::AuthController::EmailListOptions.new(paragraph.data||{})
    
    @user = EmailListUser.new(params[:email_list_signup])
    if (request.post? || params[:get_post]) && params[:email_list_signup]
      @user.valid?
      
      unless @options.partial_post == 'yes' && params[:partial_post]
        %w(zip first_name last_name).each do |fld|
          @user.errors.add(fld,'is missing') if @options.send(fld) == 'required' && @user.send(fld).blank?
        end
      end
      
      if @user.errors.empty?
        @target = EndUser.find_target(@user.email)
        if !@target.registered?
          @target.first_name = @user.first_name if !@user.first_name.blank? && @options.first_name != 'off'
          @target.last_name = @user.last_name if !@user.last_name.blank? && @options.last_name != 'off'
          @target.lead_source = @options.user_source unless @options.user_source.blank?
          @target.source = 'website'
          @target.user_level = 4
          @target.save
          if @options.zip != 'off' 
            adr = @target.address || EndUserAddress.new(:end_user_id => @target.id)
            adr.zip = @user.zip 
            adr.save
            if !@target.address
              @target.update_attribute(:address_id,adr.id)
            end
          end
        end
        
        # Handle Subscription
        if @options.user_subscription_id
          sub = UserSubscription.find_by_id(@options.user_subscription_id)
          sub.subscribe_user(@target,:ip_address => request.remote_ip) if sub
        end
        
        unless @options.tags.blank?
          @target.tag_names_add(@options.tags)
        end

        if !editor? && paragraph.update_action_count > 0
          paragraph.run_triggered_actions(@target,'action',@target)
        end
        
        unless @options.partial_post == 'yes' && params[:partial_post]
          if @options.destination_page_id 
            redirect_paragraph :site_node => @options.destination_page_id
            return
          else
            @submitted = @options.success_message
          end
        end
        
      end
      
    end

    render_paragraph :text => email_list_feature(:email_list => @user,
                                                 :options => @options,
                                                 :submitted => @submitted)
  end
  
  class EmailListUser < HashModel
    default_options :email => nil,:zip => nil, :first_name => nil, :last_name => nil
    validates_presence_of :email
    validates_as_email :email
  end
  
  def splash
    options = Editor::AuthController::SplashOptions.new(paragraph.data||{})
    
    if !options.splash_page_id || options.cookie_name.blank?
      if editor? 
        render_paragraph :text => 'Configure Paragraph'
      else
        render_paragraph :nothing => true
      end
      return 
    end 

    if editor?
      render_paragraph :text => '[Splash Page]'
    else
      if params[:no_splash]
        cookies[options.cookie_name.to_sym]= { :value => 'set', :expires => 1.year.from_now }
        render_paragraph :nothing => true
      elsif cookies[options.cookie_name.to_sym]
        render_paragraph :nothing => true
      else
        cookies[options.cookie_name.to_sym]= { :value => 'set', :expires => 1.year.from_now }
        redirect_paragraph :site_node => options.splash_page_id
      end
    end   
  end  
  
end