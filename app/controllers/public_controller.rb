# Copyright (C) 2009 Pascal Rettig.

require 'mime/types'

class PublicController < ApplicationController
  skip_before_filter :context_translate_before
  skip_after_filter :context_translate_after
  skip_before_filter :check_ssl
  skip_after_filter :save_anonymous_tags
 
  helper :paragraph
  
  def stylesheet 
  	site_template_id = params[:path][0].to_s
    lang = params[:path][1] || session[:cms_language] || Configuration.languages[0]
    editor = params[:editor] || false
    
    headers['Content-Type'] = 'text/css'
    
    if CMS_CACHE_ACTIVE 
        @css = DataCache.get_container("SiteTemplate",":#{site_template_id}:#{lang}:#{editor ? 1:0}")
    end
    
    unless @css 
      begin
        if site_template_id[0..0] == "f"
          @css = SiteFeature.find(site_template_id[1..-1]).rendered_css
        else
          @css = SiteTemplate.render_template_css(site_template_id.to_i,lang,!editor)
        end
        if CMS_CACHE_ACTIVE
          DataCache.put_container("SiteTemplate",":#{site_template_id}:#{lang}:#{editor ? 1:0}",@css)
        end
      rescue ActiveRecord::RecordNotFound => e
        render :layout => false, :text => "Stylesheet not found", :status => 404
        return
      end
    end
     
    render :layout=> false, :text => @css
  end
  
  def calendar
    @calendar_language = session[:cms_language] || Configuration.languages[0] || 'en'
    render :action => 'calendar', :layout => false
  end
  
  
  def image
    if params[:domain_id].to_i != Configuration.domain_id.to_i
      render :inline => 'File not found', :status => 404
      return
    end
    
    filename = params[:path][-1] # Filename is always the last argument
    size = params[:path][-2] # We always have a size
    prefix = params[:path][0..-3].join("/")
    
    
    df = DomainFile.find_by_prefix_and_filename(prefix,filename)
    sz = DomainFileSize.find_by_size_name(size)
    
    if df && sz
      name = sz.execute(df)
      if df.mime_type.blank?
        name = df.filename(sz.size_name)
        mime_types =  MIME::Types.type_for(name) 
        mime_type = mime_types[0] ? mime_types[0].to_s : 'application/octet-stream'
      else
        mime_type = df.mime_type
      end
      
      render :nothing => true
      if USE_X_SEND_FILE
        x_send_file(name,:type => mime_type,:disposition => 'inline',:filename => df.name)    
      else
        send_file(name,:type => mime_type,:disposition => 'inline',:filename => df.name)    
      end   
    else
      render :inline => 'File not found', :status => 404
    end    
  end
  
  def file_store
  
    # Only editors can access the file store directly
    return render(:inline => 'File not found', :status => 404) unless myself.editor?
    
    if (@file_param = params[:prefix][-1].split(":")).length == 2
      @size = @file_param[1] 
      @prefix 
      @prefix = params[:prefix][0..-2].push(@file_param[0]).join("/")
    else
      @size = nil
      @prefix = params[:prefix][0..-1].join("/")
    end
    @df = DomainFile.find_by_prefix_and_private(@prefix,0)
    
    
    if @df && !File.exists?(@df.filename(@size)) 
      sz = DomainFileSize.find_by_size_name(@size)
      if @df && sz
        sz.execute(@df)    
      end
    end

    # Show a 404 if theres no file
    return render(:inline => 'File not found', :status => 404) unless @df && File.exists?(@df.filename(@size))

    
    abs_name = @df.filename(@size)
    if @df.mime_type.blank?
      mime_types =  MIME::Types.type_for(abs_name) 
      mime_type = mime_types[0] ? mime_types[0].to_s : 'application/octet-stream'
    else
      mime_type = @df.mime_type
    end
    
    render :nothing => true if RAILS_ENV == 'test'
    
    if USE_X_SEND_FILE
      x_send_file(abs_name,:type => mime_type,:disposition => 'inline',:filename => @df.name)    
    else
      send_file(abs_name,:type => mime_type,:disposition => 'inline',:filename => @df.name)    
    end      
    
  end
  
end