# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".expand" do
    {
      "empty doc" => {
        :input => {},
        :output => {}
      },
      "coerced IRI" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => "c"
        },
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" =>"http://example.com/c"}
        }
      },
      "coerced IRI in array" => {
        :input => {
          "@context" => {
            "a" => {"@id" => "http://example.com/a"},
            "b" => {"@id" => "http://example.com/b", "@type" => "@id"},
            "c" => {"@id" => "http://example.com/c"},
          },
          "@id" => "a",
          "b"   => ["c"]
        },
        :output => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => [{"@id" => "http://example.com/c"}]
        }
      },
      "empty term" => {
        :input => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :output => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        }
      },
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.expand(params[:input], nil, :debug => @debug)
        JSON.parse(jld).should produce(params[:output], @debug)
      end
    end
  end
  
  describe ".compact" do
    {
      "prefix" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" => "http://example.com/c"}
        },
        :context => {"ex" => "http://example.com/"},
        :output => {
          "@context" => {"ex" => "http://example.com/"},
          "@id" => "ex:a",
          "ex:b" => {"@id" => "ex:c"}
        }
      },
      "term" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => {"@id" => "http://example.com/c"}
        },
        :context => {"b" => "http://example.com/b"},
        :output => {
          "@context" => {"b" => "http://example.com/b"},
          "@id" => "http://example.com/a",
          "b" => {"@id" => "http://example.com/c"}
        }
      },
      "@id coercion" => {
        :input => {
          "@id" => "http://example.com/a",
          "http://example.com/b" => "http://example.com/c"
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@type" => "@id"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@type" => "@id"}},
          "@id" => "http://example.com/a",
          "b" => "http://example.com/c"
        }
      },
      "xsd:date coercion" => {
        :input => {
          "http://example.com/b" => {"@literal" => "2012-01-04", "@type" => "xsd:date"}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@type" => "xsd:date"}},
          "b" => "2012-01-04"
        }
      },
      "@list coercion" => {
        :input => {
          "http://example.com/b" => {"@list" => ["c", "d"]}
        },
        :context => {"b" => {"@id" => "http://example.com/b", "@list" => true}},
        :output => {
          "@context" => {"b" => {"@id" => "http://example.com/b", "@list" => true}},
          "b" => ["c", "d"]
        }
      },
      "empty term" => {
        :input => {
          "@id" => "http://example.com/",
          "@type" => "#{RDF::RDFS.Resource}"
        },
        :context => {"" => "http://example.com/"},
        :output => {
          "@context" => {"" => "http://example.com/"},
          "@id" => "",
          "@type" => "#{RDF::RDFS.Resource}"
        },
      }
    }.each_pair do |title, params|
      it title do
        jld = JSON::LD::API.compact(params[:input], params[:context], :debug => @debug)
        JSON.parse(jld).should produce(params[:output], @debug)
      end
    end

    it "uses referenced context" do
      ctx = StringIO.new(%q({"@context": {"b": "http://example.com/b"}}))
      input = {
        "http://example.com/b" => "c"
      }
      expected = {
        "@context" => "http://example.com/context",
        "b" => "c"
      }
      JSON::LD::EvaluationContext.any_instance.stub(:open).with("http://example.com/context").and_yield(ctx)
      jld = JSON::LD::API.compact(input, "http://example.com/context", :debug => @debug, :validate => true)
      JSON.parse(jld).should produce(expected, @debug)
    end
  end
  
  describe ".frame", :pending => true do
  end
  
  describe ".normalize", :pending => true do
  end
  
  describe ".triples" do
    it "FIXME"
  end
  
  context "Test Files" do
    Dir.glob(File.expand_path(File.join(File.dirname(__FILE__), 'test-files/*-input.*'))) do |filename|
      test = File.basename(filename).sub(/-input\..*$/, '')
      frame = filename.sub(/-input\..*$/, '-frame.json')
      framed = filename.sub(/-input\..*$/, '-framed.json')
      compacted = filename.sub(/-input\..*$/, '-compacted.json')
      context = filename.sub(/-input\..*$/, '-context.json')
      expanded = filename.sub(/-input\..*$/, '-expanded.json')
      automatic = filename.sub(/-input\..*$/, '-automatic.json')
      ttl = filename.sub(/-input\..*$/, '-rdf.ttl')
      
      context test do
        before(:all) do
        end

        it "compacts" do
          jld = JSON::LD::API.compact(File.open(filename), File.open(context), :debug => @debug)
          JSON.parse(jld).should produce(JSON.load(File.open(compacted)), @debug)
        end if File.exist?(compacted) && File.exist?(context)
        
        it "expands" do
          jld = JSON::LD::API.expand(File.open(filename), (File.open(context) if context), :debug => @debug)
          JSON.parse(jld).should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(expanded)
        
        it "frame", :pending => true do
          jld = JSON::LD::API.frame(File.open(filename), File.open(frame), :debug => @debug)
          jld.should produce(JSON.load(File.open(expanded)), @debug)
        end if File.exist?(framed) && File.exist?(frame)

        it "Turtle" do
          RDF::Graph.load(filename, :debug => @debug).should be_equivalent_graph(RDF::Graph.load(ttl), :trace => @debug)
        end if File.exist?(ttl)
      end
    end
  end
end
