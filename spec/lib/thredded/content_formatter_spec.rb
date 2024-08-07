# frozen_string_literal: true

require 'spec_helper'

describe Thredded::ContentFormatter do
  module ViewContextStub
    def main_app; end
  end

  def format_post_content(post)
    Thredded::ContentFormatter.new(
      ViewContextStub,
      users_provider: ::Thredded::UsersProvider,
      users_provider_scope: post.readers
    ).format_content(post.content)
  end

  def format_content(content)
    Thredded::ContentFormatter.new(ViewContextStub).format_content(content)
  end

  context 'various content from post_contents.yml' do
    YAML.load_file("#{File.dirname(__FILE__)}/post_contents.yml").each do |title, contents|
      it "renders: '#{title}'" do
        @post = build(:post)
        @post.content = contents[0]
        expected_html = contents[1]

        resulting_parsed_html = parsed_html(format_post_content(@post))
        expected_parsed_html  = parsed_html(expected_html)

        expect(resulting_parsed_html).to eq(expected_parsed_html)
      end
    end

    def parsed_html(html)
      Nokogiri::HTML::DocumentFragment.parse(html, &:noblanks)
        .to_html
        .gsub(/^\s*/, '')
        .gsub(/\s*$/, '')
        .gsub(/^$\n/, '')
    end
  end

  context '@-mentions' do
    around do |ex|
      user_path_was = Thredded.instance_variable_get(:@user_path)
      ex.call
    ensure
      Thredded.user_path = user_path_was
    end

    it 'links @names of members' do
      Thredded.user_path = ->(user) { "/whois/#{user.name}" }
      post_content = '@"sam 1" and @joe. But not @unknown, email@jane.com, email@joe.com, <code>@joe</code>.'
      sam = build_stubbed(:user, name: 'sam 1')
      joe = build_stubbed(:user, name: 'joe')
      post = build_stubbed(:post, content: post_content)
      expected_html = '<p><a href="/whois/sam%201">@"sam 1"</a> and <a href="/whois/joe">@joe</a>. But not @unknown, ' \
'<a href="mailto:email@jane.com">email@jane.com</a>, <a href="mailto:email@joe.com">email@joe.com</a>, ' \
'<code>@joe</code>.</p>'

      expect(::Thredded::UsersProvider).to receive(:call)
        .with(['sam 1', 'joe', 'unknown'], kind_of(ActiveRecord::Relation))
        .and_return([sam, joe])

      expect(format_post_content(post)).to eq expected_html
    end
  end

  context 'onebox' do
    let(:xkcd_url) { 'https://xkcd.com/327/' }

    before do
      stub_request(:get, "#{xkcd_url}info.0.json")
        .to_return(body: File.read('spec/fixtures/network/xkcd327-response.json'))
    end

    context 'oneboxes a URL on its own line' do
      it 'when it is the only line' do
        expect(format_content(xkcd_url)).to include('onebox')
      end

      it 'with \nEOF after' do
        expect(format_content("#{xkcd_url}\n")).to include('onebox')
      end

      it 'with \n before and \nEOF after' do
        expect(format_content(<<~MARKDOWN)).to include('onebox')
          Hello
          #{xkcd_url}
        MARKDOWN
      end

      it 'and indented' do
        expect(format_content(<<~MARKDOWN)).to include('onebox')
          1. Hello
             #{xkcd_url}
        MARKDOWN
      end
    end

    context 'does not onebox a URL not on its own line' do
      it 'with text before on its line' do
        expect(format_content("Hello #{xkcd_url}")).not_to include('onebox')
      end
      it 'with text after on its line' do
        expect(format_content("#{xkcd_url} Hello")).not_to include('onebox')
      end
    end

    context 'with no onebox caching' do
      around do |example|
        onebox_views_cache = Thredded::HtmlPipeline::OneboxFilter.onebox_views_cache
        Thredded::HtmlPipeline::OneboxFilter.onebox_views_cache = ActiveSupport::Cache::MemoryStore.new
        example.run
        Thredded::HtmlPipeline::OneboxFilter.onebox_views_cache = onebox_views_cache
      end

      context 'if onebox throws an error' do
        subject(:formatted_content) { format_content(xkcd_url) }

        it 'renders just the url without error' do
          allow(Onebox).to receive(:preview).and_raise('Onebox internal error')
          expect(formatted_content).not_to include('onebox')
          expect(formatted_content).to include(xkcd_url)
          expect(formatted_content).to match(/href=["']#{xkcd_url}/)
        end
      end
    end

    it 'renders FakeContent sample oneboxes' do
      # This also ensures all the oneboxes are VCR'd
      expect { format_content(FakeContent::ONEBOXES.join("\n")) }.not_to raise_error
    end
  end

  context '.quote_content' do
    it 'quotes as markdown' do
      expect(described_class.quote_content('Hello')).to eq "> Hello\n\n"
    end
  end
end
