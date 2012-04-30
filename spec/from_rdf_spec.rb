# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/writer'

describe JSON::LD::API do
  describe ".fromRDF" do
    context "simple tests" do
      it "One subject IRI object" do
        input = %(<http://a/b> <http://a/c> <http://a/d> .)
        serialize(input).should produce([
        {
          '@id'         => "http://a/b",
          "http://a/c"  => [{"@id" => "http://a/d"}]
        }], @debug)
      end

      it "should generate object list" do
        input = %(@prefix : <http://example.com/> . :b :c :d, :e .)
        serialize(input).
        should produce([{
          '@id'                         => "http://example.com/b",
          "http://example.com/c" => [
            {"@id" => "http://example.com/d"},
            {"@id" => "http://example.com/e"}
          ]
        }], @debug)
      end
    
      it "should generate property list" do
        input = %(@prefix : <http://example.com/> . :b :c :d; :e :f .)
        serialize(input).
        should produce([{
          '@id'   => "http://example.com/b",
          "http://example.com/c"      => [{"@id" => "http://example.com/d"}],
          "http://example.com/e"      => [{"@id" => "http://example.com/f"}]
        }], @debug)
      end
    
      it "serializes multiple subjects" do
        input = %q(
          @prefix : <http://www.w3.org/2006/03/test-description#> .
          @prefix dc: <http://purl.org/dc/elements/1.1/> .
          <test-cases/0001> a :TestCase .
          <test-cases/0002> a :TestCase .
        )
        serialize(input).
        should produce([
          {'@id'  => "test-cases/0001", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]},
          {'@id'  => "test-cases/0002", '@type' => ["http://www.w3.org/2006/03/test-description#TestCase"]}
        ], @debug)
      end
    end
  
    context "literals" do
      it "coerces typed literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"^^ex:d .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "foo", "@type" => "http://example.com/d"}]
        }], @debug)
      end

      it "coerces integer" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [1]
        }], @debug)
      end

      it "coerces boolean" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b true .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [true]
        }], @debug)
      end

      it "coerces decmal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "1.0", "@type" => "http://www.w3.org/2001/XMLSchema#decimal"}]
        }], @debug)
      end

      it "coerces double" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b 1.0e0 .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [1.0E0]
        }], @debug)
      end
    
      it "encodes language literal" do
        input = %(@prefix ex: <http://example.com/> . ex:a ex:b "foo"@en-us .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"    => [{"@value" => "foo", "@language" => "en-us"}]
        }], @debug)
      end
    end

    context "anons" do
      it "should generate bare anon" do
        input = %(@prefix : <http://example.com/> . _:a :a :b .)
        serialize(input).should produce([{
          "@id" => "_:a",
          "http://example.com/a"  => [{"@id" => "http://example.com/b"}]
        }], @debug)
      end
    
      it "should generate anon as object" do
        input = %(@prefix : <http://example.com/> . :a :b _:a . _:a :c :d .)
        serialize(input).should produce([
          {
            "@id" => "_:a",
            "http://example.com/c"  => [{"@id" => "http://example.com/d"}]
          },
          {
            "@id" => "http://example.com/a",
            "http://example.com/b"  => [{"@id" => "_:a"}]
          },
        ], @debug)
      end
    end
  
    context "lists" do
      it "should generate literal list" do
        input = %(
          @prefix : <http://example.com/> .
          @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
          :a :b ("apple" "banana")  .
        )
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => [{
            "@list" => [
              {"@value" => "apple"},
              {"@value" => "banana"}
            ]
          }]
        }], @debug)
      end
    
      it "should generate iri list" do
        input = %(@prefix : <http://example.com/> . :a :b (:c) .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => [{
            "@list" => [
              {"@id" => "http://example.com/c"}
            ]
          }]
        }], @debug)
      end
    
      it "should generate empty list" do
        input = %(@prefix : <http://example.com/> . :a :b () .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => [{"@list" => []}]
        }], @debug)
      end
    
      it "should generate single element list" do
        input = %(@prefix : <http://example.com/> . :a :b ( "apple" ) .)
        serialize(input).should produce([{
          '@id'   => "http://example.com/a",
          "http://example.com/b"  => [{"@list" => [{"@value" => "apple"}]}]
        }], @debug)
      end
    
      it "should generate single element list without @type" do
        input = %(
        @prefix : <http://example.com/> . :a :b ( _:a ) . _:a :b "foo" .)
        serialize(input).should produce([
          {
            '@id'   => "_:a",
            "http://example.com/b"  => [{"@value" => "foo"}]
          },
          {
            '@id'   => "http://example.com/a",
            "http://example.com/b"  => [{"@list" => [{"@id" => "_:a"}]}]
          },
        ], @debug)
      end
    end
    
    context "quads" do
      {
        "simple named graph" => {
          :input => %(
            <http://example.com/a> <http://example.com/b> <http://example.com/c> <http://example.com/U> .
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@id" => "http://example.com/c"}]
              }]
            }
          ]
        },
        "with properties" => {
          :input => %(
            <http://example.com/a> <http://example.com/b> <http://example.com/c> <http://example.com/U> .
            <http://example.com/U> <http://example.com/d> <http://example.com/e> .
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@id" => "http://example.com/c"}]
              }],
              "http://example.com/d" => [{"@id" => "http://example.com/e"}]
            }
          ]
        },
        "with lists" => {
          :input => %(
            <http://example.com/a> <http://example.com/b> _:a <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/c> <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/U> .
            <http://example.com/U> <http://example.com/d> _:b .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/e> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [{
                "@id" => "http://example.com/a",
                "http://example.com/b" => [{"@list" => [{"@id" => "http://example.com/c"}]}]
              }],
              "http://example.com/d" => [{"@list" => [{"@id" => "http://example.com/e"}]}]
            }
          ]
        },
        "Two Graphs with same subject and lists" => {
          :input => %(
            <http://example.com/a> <http://example.com/b> _:a <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/c> <http://example.com/U> .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/U> .
            <http://example.com/a> <http://example.com/b> _:b <http://example.com/V> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> <http://example.com/e> <http://example.com/V> .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> <http://example.com/V> .
          ),
          :output => [
            {
              "@id" => "http://example.com/U",
              "@graph" => [
                {
                  "@id" => "http://example.com/a",
                  "http://example.com/b" => [{
                    "@list" => [{"@id" => "http://example.com/c"}]
                  }]
                }
              ]
            },
            {
              "@id" => "http://example.com/V",
              "@graph" => [
                {
                  "@id" => "http://example.com/a",
                  "http://example.com/b" => [{
                    "@list" => [{"@id" => "http://example.com/e"}]
                  }]
                }
              ]
            }
          ]
        },
      }.each_pair do |name, properties|
        it name do
          r = serialize(properties[:input], :reader => RDF::NQuads::Reader)
          r.should produce(properties[:output], @debug)
        end
      end
    end

    context "notType option" do
      it "uses @type if set to false" do
        input = %(@prefix ex: <http://example.com/> . ex:a a ex:b .)
        serialize(input, :notType => false).should produce([{
          '@id'   => "http://example.com/a",
          "@type"    => ["http://example.com/b"]
        }], @debug)
      end
      
      it "does not use @type if set to true" do
        input = %(@prefix ex: <http://example.com/> . ex:a a ex:b .)
        serialize(input, :notType => true).should produce([{
          '@id'   => "http://example.com/a",
          RDF.type.to_s    => [{"@id" => "http://example.com/b"}]
        }], @debug)
      end
    end
  end

  def parse(input, options = {})
    reader = options[:reader] || RDF::Turtle::Reader
    RDF::Repository.new << reader.new(input, options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, options = {})
    g = ntstr.is_a?(String) ? parse(ntstr, options) : ntstr
    @debug = [] << g.dump(:trig)
    statements = g.each_statement.to_a
    JSON::LD::API.fromRDF(statements, nil, options.merge(:debug => @debug))
  end
end
