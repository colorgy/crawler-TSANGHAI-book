require 'crawler_rocks'
require 'pry'
require 'json'
require 'hashie'

require 'book_toolkit'

require 'thread'
require 'thwait'

class TsanghaiBookCrawler
  def initialize update_progress: nil, after_each: nil
    @update_progress_proc = update_progress
    @after_each_proc = after_each

    @search_url = "https://www.tsanghai.com.tw/model/pagesAjax.php"
    @search_result = "https://www.tsanghai.com.tw/search_result.php"
  end

  def books
    @books = {}
    @threads = []

    # load datas
    json_match_regex = /(?<=JSON2\.parse\(\')(.+)(?=\'\))/
    r = RestClient::Request.execute(url: @search_url, method: :post, verify_ssl: false, payload: payload)
    data = parse_json(r.match(json_match_regex).to_s)

    page_count = data.pages.Pages
    books_count = data.pages.RecordCount.to_i

    # (1..10).each do |i|
    (1..page_count).each do |i|
      puts "#{i} / #{page_count}"
      sleep(1) until (
        @threads.delete_if { |t| !t.status };  # remove dead (ended) threads
        @threads.count < (ENV['MAX_THREADS'] || 25)
      )
      @threads << Thread.new do
        r = RestClient::Request.execute(url: @search_url, method: :post, verify_ssl: false, payload: payload(i))
        data = parse_json(r.match(json_match_regex).to_s)

        data.json.each do |book|
          isbn = nil; invalid_isbn = nil
          begin
            isbn = BookToolkit.to_isbn13(book.ISBN)
          rescue Exception => e
            invalid_isbn = book.ISBN
          end

          @books[book.NumberID] = {
            name: book.Name,
            original_price: book.Pricing.to_i,
            author: book.Author,
            edition: book.Revision.to_i,
            external_image_url: URI.join(@search_result, book.path+book.SImg).to_s,
            publisher: book.Publishers,
            isbn: isbn,
            invalid_isbn: invalid_isbn,
            internal_code: book.NumberID,
            url: "https://www.tsanghai.com.tw/book_detail.php?c=#{book.cID}&no=#{book.ID}#p=#{book.p}",
            known_supplier: 'tsanghai'
          }

          @after_each_proc.call(book: @books[book.NumberID]) if @after_each_proc
        end
      end # end each Thread
    end

    ThreadsWait.all_waits(*@threads)
    @books.values
  end

  def parse_json json_raw
    Hashie::Mash.new(
      JSON.parse(
        json_raw.gsub(/\\\\b/,'\\b')\
        .gsub(/\\\\t/,'\\t').gsub(/\\\\n/,'\\n')
        .gsub(/\\\\f/,'\\f').gsub(/\\\\\r/,'\\r')
        .gsub(/\\\\"/,'\\"').gsub(/\\\\\\\\/,'\\\\')
        .gsub(/\\\\u/,'\\u').gsub(/\\\"/,'"')
        .gsub(/\\\\\//,'/')
      )
    )
  end

  def payload page_num=1
    {
      args: [
        'sendBookSearch',
        {
          bookSearch: "",
          "page" => page_num,
          "cie" => false
        }.to_json
      ]
    }
  end
end

# cc = TsanghaiBookCrawler.new
# File.write('tsanghai_books.json', JSON.pretty_generate(cc.books))
