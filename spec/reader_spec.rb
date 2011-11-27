# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::Reader do
  before :each do
    @reader = JSON::LD::Reader.new(StringIO.new(""))
  end

  it_should_behave_like RDF_Reader

  describe ".for" do
    formats = [
      :json, :ld, :jsonld,
      'etc/doap.json', "etc/doap.jsonld",
      {:file_name      => 'etc/doap.json'},
      {:file_name      => 'etc/doap.jsonld'},
      {:file_extension => 'json'},
      {:file_extension => 'jsonld'},
      {:content_type   => 'application/ld+json'},
      {:content_type   => 'application/x-ld+json'},
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        RDF::Reader.for(arg).should == JSON::LD::Reader
      end
    end
  end

  context :interface do
    subject { %q({
      "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
       "@subject": "_:bnode1",
       "@type": "foaf:Person",
       "foaf:homepage": "http://example.com/bob/",
       "foaf:name": "Bob"
     }) }

    describe "#initialize" do
      it "yields reader given string" do
        inner = mock("inner")
        inner.should_receive(:called).with(JSON::LD::Reader)
        JSON::LD::Reader.new(subject) do |reader|
          inner.called(reader.class)
        end
      end

      it "yields reader given IO" do
        inner = mock("inner")
        inner.should_receive(:called).with(JSON::LD::Reader)
        JSON::LD::Reader.new(StringIO.new(subject)) do |reader|
          inner.called(reader.class)
        end
      end

      it "returns reader" do
        JSON::LD::Reader.new(subject).should be_a(JSON::LD::Reader)
      end
    end

    describe "#each_statement" do
      it "yields statements" do
        inner = mock("inner")
        inner.should_receive(:called).with(RDF::Statement).exactly(3)
        JSON::LD::Reader.new(subject).each_statement do |statement|
          inner.called(statement.class)
        end
      end
    end

    describe "#each_triple" do
      it "yields triples" do
        inner = mock("inner")
        inner.should_receive(:called).exactly(3)
        JSON::LD::Reader.new(subject).each_triple do |subject, predicate, object|
          inner.called(subject.class, predicate.class, object.class)
        end
      end
    end
  end

  context :parsing do
    context "literals" do
      {
        "plain literal" =>
        [
          %q({"@subject": "http://greggkellogg.net/foaf#me", "http://xmlns.com/foaf/0.1/name": "Gregg Kellogg"}),
          %q(<http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        "explicit plain literal" =>
        [
          %q({"http://xmlns.com/foaf/0.1/name": {"@literal": "Gregg Kellogg"}}),
          %q(_:a <http://xmlns.com/foaf/0.1/name> "Gregg Kellogg" .)
        ],
        "language tagged literal" =>
        [
          %q({"http://www.w3.org/2000/01/rdf-schema#label": {"@literal": "A plain literal with a lang tag.", "@language": "en-us"}}),
          %q(_:a <http://www.w3.org/2000/01/rdf-schema#label> "A plain literal with a lang tag."@en-us .)
        ],
        "I18N literal with language" =>
        [
          %q([{
            "@subject": "http://greggkellogg.net/foaf#me",
            "http://xmlns.com/foaf/0.1/knows": {"@iri": "http://www.ivan-herman.net/foaf#me"}
          },{
            "@subject": "http://www.ivan-herman.net/foaf#me",
            "http://xmlns.com/foaf/0.1/name": {"@literal": "Herman Iván", "@language": "hu"}
          }]),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
            <http://www.ivan-herman.net/foaf#me> <http://xmlns.com/foaf/0.1/name> "Herman Iv\u00E1n"@hu .
          )
        ],
        "explicit datatyped literal" =>
        [
          %q({
            "@subject":  "http://greggkellogg.net/foaf#me",
            "http://purl.org/dc/terms/created":  {"@literal": "1957-02-27", "@datatype": "http://www.w3.org/2001/XMLSchema#date"}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://purl.org/dc/terms/created> "1957-02-27"^^<http://www.w3.org/2001/XMLSchema#date> .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "prefixes" do
      {
        "empty prefix" => [
          %q({"@context": {"": "http://example.com/default#"}, ":foo": "bar"}),
          %q(_:a <http://example.com/default#foo> "bar" .)
        ],
        "empty suffix" => [
          %q({"@context": {"prefix": "http://example.com/default#"}, "prefix:": "bar"}),
          %q(_:a <http://example.com/default#> "bar" .)
        ],
        "prefix:suffix" => [
          %q({"@context": {"prefix": "http://example.com/default#"}, "prefix:foo": "bar"}),
          %q(_:a <http://example.com/default#foo> "bar" .)
        ]
      }.each_pair do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "overriding keywords" do
      {
        "'url' for @subject, 'a' for @type" =>
        [
          %q({
            "@context": {"url": "@subject", "a": "@type", "name": "http://schema.org/name"},
            "url": "http://example.com/about#gregg",
            "a": "http://schema.org/Person",
            "name": "Gregg Kellogg"
          }),
          %q(
            <http://example.com/about#gregg> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://schema.org/Person> .
            <http://example.com/about#gregg> <http://schema.org/name> "Gregg Kellogg" .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "chaining" do
      {
        "explicit subject" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": {
              "@subject": "http://www.ivan-herman.net/foaf#me",
              "foaf:name": "Ivan Herman"
            }
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
            <http://www.ivan-herman.net/foaf#me> <http://xmlns.com/foaf/0.1/name> "Ivan Herman" .
          )
        ],
        "implicit subject" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": {
              "foaf:name": "Manu Sporny"
            }
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://xmlns.com/foaf/0.1/name> "Manu Sporny" .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "multiple values" do
      {
        "literals" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": ["Manu Sporny", "Ivan Herman"]
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> "Manu Sporny" .
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> "Ivan Herman" .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "lists" do
      {
        "Empty" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": {"@list": []}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
        "single value" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": {"@list": ["Manu Sporny"]}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Manu Sporny" .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
        "multiple values" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": "http://greggkellogg.net/foaf#me",
            "foaf:knows": {"@list": ["Manu Sporny", "Dave Longley"]}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> _:a .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Manu Sporny" .
            _:a <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> _:b .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#first> "Dave Longley" .
            _:b <http://www.w3.org/1999/02/22-rdf-syntax-ns#rest> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end

    context "context" do
      {
        "@base expansion" =>
        [
          %q({
            "@context": {
              "@base":  "http://greggkellogg.net/foaf",
              "doap": "http://usefulinc.com/ns/doap#"
            },
            "@subject":  "#me",
            "doap:homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        "@vocab expansion" =>
        [
          %q({
            "@context": {
              "@vocab": "http://usefulinc.com/ns/doap#"
            },
            "@subject":  "http://greggkellogg.net/foaf#me",
            "homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        "@base and @vocab expansion" =>
        [
          %q({
            "@context": {
              "@base":  "http://greggkellogg.net/foaf",
              "@vocab": "http://usefulinc.com/ns/doap#"
            },
            "@subject":  "#me",
            "homepage":  {"@iri": "http://github.com/gkellogg/"}
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://usefulinc.com/ns/doap#homepage> <http://github.com/gkellogg/> .
          )
        ],
        "@iri coersion" =>
        [
          %q({
            "@context": {
              "foaf": "http://xmlns.com/foaf/0.1/",
              "@coerce":  { "@iri": "foaf:knows"}
            },
            "@subject":  "http://greggkellogg.net/foaf#me",
            "foaf:knows":  "http://www.ivan-herman.net/foaf#me"
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://xmlns.com/foaf/0.1/knows> <http://www.ivan-herman.net/foaf#me> .
          )
        ],
        "datatype coersion" =>
        [
          %q({
            "@context": {
              "dcterms":  "http://purl.org/dc/terms/",
              "xsd":      "http://www.w3.org/2001/XMLSchema#",
              "@coerce":  { "xsd:date": "dcterms:created"}
            },
            "@subject":  "http://greggkellogg.net/foaf#me",
            "dcterms:created":  "1957-02-27"
          }),
          %q(
            <http://greggkellogg.net/foaf#me> <http://purl.org/dc/terms/created> "1957-02-27"^^<http://www.w3.org/2001/XMLSchema#date> .
          )
        ],
        "sub-objects with context" => [
          %q({
            "@context": {"foo": "http://example.com/foo"},
            "foo":  {
              "@context": {"foo": "http://example.org/foo"},
              "foo": "bar"
            }
          }),
          %q(
            _:a <http://example.com/foo> _:b .
            _:b <http://example.org/foo> "bar" .
          )
        ],
        "contexts with a list processed in order" => [
          %q({
            "@context": [
              {"foo": "http://example.com/foo"},
              {"foo": "http://example.org/foo"}
            ],
            "foo":  "bar"
          }),
          %q(
            _:b <http://example.org/foo> "bar" .
          )
        ],
        "term definition resolves term as IRI" => [
          %q({
            "@context": [
              {"foo": "http://example.com/foo"},
              {"bar": "foo"}
            ],
            "bar":  "bar"
          }),
          %q(
            _:b <http://example.com/foo> "bar" .
          )
        ],
        "term definition resolves prefix as IRI" => [
          %q({
            "@context": [
              {"foo": "http://example.com/foo#"},
              {"bar": "foo:bar"}
            ],
            "bar":  "bar"
          }),
          %q(
            _:b <http://example.com/foo#bar> "bar" .
          )
        ],
        "IRI resolution uses term from active context, not current context" => [
          %q({
            "@context": [
              {"foo": "http://example.com/foo#"},
              {
                "foo": "not-this#",
                "bar": "foo:bar"
              }
            ],
            "bar":  "bar"
          }),
          %q(
            _:b <http://example.com/foo#bar> "bar" .
          )
        ],
        "@language" => [
          %q({
            "@context": {
              "foo": "http://example.com/foo#",
              "@language": "en"
            },
            "foo:bar":  "baz"
          }),
          %q(
            _:a <http://example.com/foo#bar> "baz"@en .
          )
        ],
        "@language with override" => [
          %q({
            "@context": {
              "foo": "http://example.com/foo#",
              "@language": "en"
            },
            "foo:bar":  {"@literal": "baz", "@language": "fr"}
          }),
          %q(
            _:a <http://example.com/foo#bar> "baz"@fr .
          )
        ],
        "@language with plain" => [
          %q({
            "@context": {
              "foo": "http://example.com/foo#",
              "@language": "en"
            },
            "foo:bar":  {"@literal": "baz"}
          }),
          %q(
            _:a <http://example.com/foo#bar> "baz" .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
      
      context "coercion" do
        context "@coerce block DEPRECATED" do
          {
            "dt with term" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "xsd:date": "foo"
                  }
                },
                "foo": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#> "bar"^^xsd:date ] .
              )
            ],
            "dt with prefix:suffix" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "xsd:date": "foo:bar"
                  }
                },
                "foo:bar": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> "bar"^^xsd:date ] .
              )
            ],
            "dt with IRI" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#bar",
                  "@coerce": {
                    "xsd:date": "http://example.org/foo#bar"
                  }
                },
                "http://example.org/foo#bar": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> "bar"^^xsd:date ] .
              )
            ],
            "dt with list" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#",
                  "bar": "http://example.org/bar#",
                  "@coerce": {
                    "xsd:date": ["foo", "bar"]
                  }
                },
                "foo": "bar",
                "bar": "baz"
              }),
              %q(
              @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
              [
                <http://example.org/foo#> "bar"^^xsd:date;
                <http://example.org/bar#> "baz"^^xsd:date;
              ] .
              )
            ],
            "@iri with term" => [
              %q({
                "@context": {
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "@iri": "foo"
                  }
                },
                "foo": "bar"
              }),
              %q(
                _:a <http://example.org/foo#> <bar> .
              )
            ],
            "coercion without term definition" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "dc": "http://purl.org/dc/terms/",
                  "@coerce": {
                    "xsd:date": "dc:date"
                  }
                },
                "dc:date": "2011-11-23"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                @prefix dc: <http://purl.org/dc/terms/> .
                [ dc:date "2011-11-23"^^xsd:date] .
              )
            ],
          }.each do |title, (js, nt)|
            it title do
              parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
            end
          end
        end

        context "term def with @iri + @coerce" do
          {
            "vocab expansion" => [
              %q({
                "@context": [
                  {"@vocab": "http://example.org/"},
                  {"foo": {}}
                ],
                "foo": "bar"
              }),
              %q(
                _:a <http://example.org/foo> "bar" .
              )
            ],
            "dt with term" => [
              %q({
                "@context": [
                  {"date": "http://www.w3.org/2001/XMLSchema#date", "term": "http://example.org/foo#"},
                  {"foo": {"@iri": "term", "@coerce": "date"}}
                ],
                "foo": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#> "bar"^^xsd:date ] .
              )
            ],
            "dt with prefix:suffix" => [
              %q({
                "@context": [
                  {"xsd": "http://www.w3.org/2001/XMLSchema#", "prefix": "http://example.org/foo#"},
                  {"foo": {"@iri": "prefix:bar", "@coerce": "xsd:date"}}
                ],
                "prefix:bar": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> "bar"^^xsd:date ] .
              )
            ],
            "dt with IRI" => [
              %q({
                "@context": [
                  {"foo": {"@iri": "http://example.org/foo#bar", "@coerce": "http://www.w3.org/2001/XMLSchema#date"}}
                ],
                "http://example.org/foo#bar": "bar"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> "bar"^^xsd:date ] .
              )
            ],
            "@iri with term" => [
              %q({
                "@context": [
                  {"foo": {"@iri": "http://example.org/foo#bar", "@coerce": "@iri"}}
                ],
                "foo": "bar"
              }),
              %q(
                _:a <http://example.org/foo#bar> <bar> .
              )
            ],
            "coercion without term definition" => [
              %q({
                "@context": [
                  {
                    "xsd": "http://www.w3.org/2001/XMLSchema#",
                    "dc": "http://purl.org/dc/terms/"
                  },
                  {
                    "dc:date": {"@coerce": "xsd:date"}
                  }
                ],
                "dc:date": "2011-11-23"
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                @prefix dc: <http://purl.org/dc/terms/> .
                [ dc:date "2011-11-23"^^xsd:date] .
              )
            ],
          }.each do |title, (js, nt)|
            it title do
              parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
            end
          end
        end
      end

      context "lists" do
        context "@coerce block DEPRECATED" do
          {
            "dt with term" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "xsd:date": "foo",
                    "@list":    "foo"
                  }
                },
                "foo": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#> ("bar"^^xsd:date) ] .
              )
            ],
            "dt with prefix:suffix" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "xsd:date": "foo:bar",
                    "@list":    "foo:bar"
                  }
                },
                "foo:bar": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> ("bar"^^xsd:date) ] .
              )
            ],
            "dt with IRI" => [
              %q({
                "@context": {
                  "xsd": "http://www.w3.org/2001/XMLSchema#",
                  "foo": "http://example.org/foo#bar",
                  "@coerce": {
                    "xsd:date": "http://example.org/foo#bar",
                    "@list":    "http://example.org/foo#bar"
                  }
                },
                "http://example.org/foo#bar": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> ("bar"^^xsd:date) ] .
              )
            ],
            "@iri with term" => [
              %q({
                "@context": {
                  "foo": "http://example.org/foo#",
                  "@coerce": {
                    "@iri": "foo",
                    "@list": "foo"
                  }
                },
                "foo": ["bar"]
              }),
              %q(
                _:a <http://example.org/foo#> (<bar>) .
              )
            ],
          }.each do |title, (js, nt)|
            it title do
              parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
            end
          end
        end

        context "term def with @iri + @coerce + @list" do
          {
            "vocab expansion" => [
              %q({
                "@context": [
                  {"@vocab": "http://example.org/"},
                  {"foo": {"@list": true}}
                ],
                "foo": ["bar"]
              }),
              %q(
                _:a <http://example.org/foo> ("bar") .
              )
            ],
            "dt with term" => [
              %q({
                "@context": [
                  {"date": "http://www.w3.org/2001/XMLSchema#date", "term": "http://example.org/foo#"},
                  {"foo": {"@iri": "term", "@coerce": "date", "@list": true}}
                ],
                "foo": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#> ("bar"^^xsd:date) ] .
              )
            ],
            "dt with prefix:suffix" => [
              %q({
                "@context": [
                  {"xsd": "http://www.w3.org/2001/XMLSchema#", "prefix": "http://example.org/foo#"},
                  {"foo": {"@iri": "prefix:bar", "@coerce": "xsd:date", "@list": true}}
                ],
                "prefix:bar": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> ("bar"^^xsd:date) ] .
              )
            ],
            "dt with IRI" => [
              %q({
                "@context": [
                  {"foo": {"@iri": "http://example.org/foo#bar", "@coerce": "http://www.w3.org/2001/XMLSchema#date", "@list": true}}
                ],
                "http://example.org/foo#bar": ["bar"]
              }),
              %q(
                @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
                [ <http://example.org/foo#bar> ("bar"^^xsd:date) ] .
              )
            ],
            "@iri with term" => [
              %q({
                "@context": [
                  {"foo": {"@iri": "http://example.org/foo#bar", "@coerce": "@iri", "@list": true}}
                ],
                "foo": ["bar"]
              }),
              %q(
                _:a <http://example.org/foo#bar> (<bar>) .
              )
            ],
          }.each do |title, (js, nt)|
            it title do
              parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
            end
          end
        end
      end

      context "remote" do
        before(:all) do
          @ctx = StringIO.new(%q({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name",
              "homepage": "http://xmlns.com/foaf/0.1/homepage",
              "avatar": "http://xmlns.com/foaf/0.1/avatar",
              "@coerce": {
                "@iri": ["homepage", "avatar"]
              }
            }
          }))
          def @ctx.content_type; "application/json"; end
          def @ctx.base_uri; "http://example.com/context"; end
        end
        
        it "retrieves and parses a remote context document" do
          js = %q(
          {
            "@context": "http://example.org/json-ld-contexts/person",
            "name": "Manu Sporny",
            "homepage": "http://manu.sporny.org/",
            "avatar": "http://twitter.com/account/profile_image/manusporny"
          }
          )
          
          ttl = %q(
            @prefix foaf: <http://xmlns.com/foaf/0.1/> .
            [
              foaf:name "Manu Sporny";
              foaf:homepage <http://manu.sporny.org/>;
              foaf:avatar <http://twitter.com/account/profile_image/manusporny>
            ] .
          )

          dbg = []
          graph = RDF::Graph.new
          r = JSON::LD::Reader.new(js, :debug => dbg)
          JSON::LD::EvaluationContext.any_instance.
            stub(:open).with("http://example.org/json-ld-contexts/person").
            and_yield(@ctx)
          
          graph << r
          graph.should be_equivalent_graph(ttl, :trace => dbg)
        end

        
        it "fails given a missing remote @context" do
          js = %q(
          {
            "@context": "http://example.org/missing-context",
            "name": "Manu Sporny",
            "homepage": "http://manu.sporny.org/",
            "avatar": "http://twitter.com/account/profile_image/manusporny"
          }
          )
          dbg = []
          graph = RDF::Graph.new
          r = JSON::LD::Reader.new(js, :debug => dbg, :validate => true)
          JSON::LD::EvaluationContext.any_instance.
            stub(:open).with("http://example.org/missing-context").
            and_raise(JSON::ParserError)
          
          lambda { graph << r }.should raise_error(RDF::ReaderError, /Failed to parse remote context/)
        end
      end
    end

    context "advanced features" do
      {
        "number syntax (decimal)" =>
        [
          %q({"@context": { "measure": "http://example/measure#"}, "measure:cups": 5.3}),
          %q(_:a <http://example/measure#cups> "5.3"^^<http://www.w3.org/2001/XMLSchema#double> .)
        ],
        "number syntax (double)" =>
        [
          %q({"@context": { "measure": "http://example/measure#"}, "measure:cups": 5.3e0}),
          %q(_:a <http://example/measure#cups> "5.3"^^<http://www.w3.org/2001/XMLSchema#double> .)
        ],
        "number syntax (integer)" =>
        [
          %q({"@context": { "chem": "http://example/chem#"}, "chem:protons": 12}),
          %q(_:a <http://example/chem#protons> "12"^^<http://www.w3.org/2001/XMLSchema#integer> .)
        ],
        "boolan syntax" =>
        [
          %q({"@context": { "sensor": "http://example/sensor#"}, "sensor:active": true}),
          %q(_:a <http://example/sensor#active> "true"^^<http://www.w3.org/2001/XMLSchema#boolean> .)
        ],
        "Array top element" =>
        [
          %q([
            {"@subject":   "http://example.com/#me", "@type": "http://xmlns.com/foaf/0.1/Person"},
            {"@subject":   "http://example.com/#you", "@type": "http://xmlns.com/foaf/0.1/Person"}
          ]),
          %q(
            <http://example.com/#me> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
            <http://example.com/#you> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
          )
        ],
        "@subject with array of objects value" =>
        [
          %q({
            "@context": {"foaf": "http://xmlns.com/foaf/0.1/"},
            "@subject": [
              {"@subject":   "http://example.com/#me", "@type": "foaf:Person"},
              {"@subject":   "http://example.com/#you", "@type": "foaf:Person"}
            ]
          }),
          %q(
            <http://example.com/#me> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
            <http://example.com/#you> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
          )
        ],
      }.each do |title, (js, nt)|
        it title do
          parse(js).should be_equivalent_graph(nt, :trace => @debug, :inputDocument => js)
        end
      end
    end
  end

  def parse(input, options = {})
    @debug = []
    graph = options[:graph] || RDF::Graph.new
    graph << JSON::LD::Reader.new(input, {:debug => @debug, :validate => true, :canonicalize => false}.merge(options))
  end
end
