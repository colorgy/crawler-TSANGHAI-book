require 'nokogiri'
require 'rest_client'
require 'json'
require_relative '../book.rb'

class THSpider
  attr_accessor :books

  def initialize
    @url = "https://www.tsanghai.com.tw/model/pagesAjax.php"
    @books = nil
    @cache_dir = 'webpages'

    if !Dir.exist?(@cache_dir)
      Dir.mkdir(@cache_dir)
    end

  end

  def initial_crawl
    action = 'sendBookSearch'
    post_obj = {"bookSearch" => " ", "page" => 1, "cie" => false}

    response = RestClient.post(
      @url,
      {'args' => [action, post_obj.to_json]}
    )

    @books = parse_json_object(response)
    @total_pages = @books["pages"]["Pages"]
    @total_books = @books["pages"]["RecordCount"]
  end

  def crawl_each_json
    @books = []

    (1..@total_pages).each do |page_num|
      action = 'sendBookSearch'
      post_obj = {"bookSearch" => " ", "page" => page_num, "cie" => false}

      response = RestClient.post(
        @url,
        {'args' => [action, post_obj.to_json]}
      )

      parse_json_object(response)["json"].each do |book_hash|

        # https://www.tsanghai.com.tw/book_detail.php?c=323&no=3373
        c_id = book_hash["cID"]
        id = book_hash["ID"]

        base_url = "https://www.tsanghai.com.tw"
        detail_url = "#{base_url}/book_detail.php?c=#{c_id}&no=#{id}"
        filename = "#{book_hash["NumberID"]}.html"
        file_path = "#{@cache_dir}/#{filename}"

        doc = nil
        if File.exist?(file_path)
          f = File.open(file_path)
          doc = Nokogiri::HTML(f.read)
        else
          detail_page = RestClient.get detail_url
          File.open(file_path, 'w') { |f| f.write(detail_page.to_s) }
          doc = Nokogiri::HTML(detail_page.to_s)
        end

        book_detail_texts = doc.css('.book_detail_text')
        book_detail_texts[1].search('br').each {|b| b.replace("\n") }
        content = book_detail_texts[1].text.strip
        book_detail_texts[2].search('br').each {|b| b.replace("\n") }
        author_intro = book_detail_texts[2].text.strip

        isbn = book_hash["ISBN"]
        isbn_13 = isbn.length == 13 ? isbn : nil
        isbn_10 = isbn.length == 10 ? isbn : nil


        @books << Book.new({
          "name" => book_hash["Name"],
          "author" => book_hash["Author"],
          "publisher" => book_hash["Publishers"],
          "year" => book_hash["Years"],
          "edition" => book_hash["Revision"],
          "cover_price" => book_hash["Pricing"],
          "price" => book_hash["OnLinePrice"],
          "book_number" => book_hash["NumberID"],
          "cover_img" => "#{base_url}/#{book_hash["path"]}#{book_hash["SImg"]}",
          "isbn_10" => isbn_10,
          "isbn_13" => isbn_13,
          "content" => content,
          "author_intro" => author_intro,
          "url" => detail_url
        }).to_hash
      end

      print "#{page_num}, "
    end
    save
  end


  private
    def parse_json_object(response)
      doc = Nokogiri::HTML(response.to_s)
      script_code = doc.css('script').text

      scr_start = script_code.index('\'')
      scr_end = script_code.rindex('\'')
      json_raw = script_code[scr_start+1..scr_end-1]
      json_clear = json_raw.gsub(/\\\\b/,'\\b').gsub(/\\\\t/,'\\t').gsub(/\\\\n/,'\\n').gsub(/\\\\f/,'\\f').gsub(/\\\\\r/,'\\r').gsub(/\\\\"/,'\\"').gsub(/\\\\\\\\/,'\\\\').gsub(/\\\\u/,'\\u').gsub(/\\\"/,'"').gsub(/\\\\\//,'/')

      return JSON.parse(json_clear)
    end

    def save
      File.open('books.json', 'w') { |f| f.write(JSON.pretty_generate(@books)) }
    end
end

spider = THSpider.new
spider.initial_crawl
spider.crawl_each_json
