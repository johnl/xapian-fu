module XapianFu
  # A XapianFu::ResultSet holds the XapianDoc objects returned from a search.
  # It acts just like an array but is decorated with useful attributes.
  class ResultSet < Array

    # The Xapian match set for this search
    attr_reader :mset
    attr_reader :current_page, :per_page
    # The total number of pages of results available for this search
    attr_reader :total_pages
    # If any spelling corrections were detected, the full collected query is provided
    # by :corrected_query, otherwise this is empty.
    attr_reader :corrected_query

    # nodoc
    def initialize(options = { })
      @mset = options[:mset]
      @current_page = options[:current_page]
      @per_page = options[:per_page]
      @corrected_query = options[:corrected_query]
      concat mset.matches.collect { |m| XapianDoc.new(m) }
    end

    # The estimated total number of matches this search could return
    def total_entries
      mset.matches_estimated
    end

    # The estimated total number of pages of results this search could return
    def total_pages
      (total_entries / per_page.to_f).round
    end

    # The previous page number, or nil if there are no previous pages available
    def previous_page
      p = current_page - 1
      p == 0 ? nil : p
    end

    # The next page number, or nil if there are no more more pages available
    def next_page
      p = current_page + 1
      p > total_pages ? nil : p
    end

    # The offset within the total results of the first result in this page
    def offset
      (current_page - 1) * per_page
    end

  end
end
