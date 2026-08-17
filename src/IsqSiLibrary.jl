module IsqSiLibrary

    using CSV
    using OrderedCollections
    using DataFrames
    using NamingConventions
 
    using NamingConventions

    const ONTOLOGY_TYPES = Dict(
        "vocabulary" => "v",
        "description" => "d"
    )

    const ONTOLOGY_COMPANION = Dict(
        "v" => "d",
        "d" => "v"
    )

    const BUNDLE_TYPES = Dict(
        "vocabulary bundle" => "vb",
        "description bundle" => "db"
    )
    
    const BUNDLE_IMPORTS = Dict(
        "vocabulary bundle" => ["vocabulary"],
        "description bundle" => ["vocabulary bundle", "description"]
    )

    struct SpaceCase <: AbstractNamingConvention end

    function NamingConventions.encode(::Type{SpaceCase}, v::AbstractString)
        return join(v, " ")
    end

    function NamingConventions.decode(::Type{SpaceCase}, s::AbstractString)
        return split(s)
    end

    function instance_name(string)
        NamingConventions.convert(SpaceCase, SnakeCase, string)
    end

    function remove_paren_text(string)
        replace(string, r" \(.*" => "")
    end

    function extract_paren_text(string)
        match(r"\(([^)]*)\)", string)[1]
    end

    export parse_csv_source
    function parse_csv_source(path)
        CSV.read(path, DataFrame)
    end

    export table_to_dict
    function table_to_dict(table, key)
        sub_keys = filter(n -> n != key, names(table))
        d = OrderedDict{String, OrderedDict{String, Any}}()
        for row in eachrow(table)
            id = OrderedDict()
            for sub_key in sub_keys
                id[sub_key] = row[sub_key]
            end
            d[row[key]] = id
        end
        d
    end

    export initialize_dictionary
    function initialize_dictionary()
        OrderedDict{String, Any}()
    end

    export construct_ontologies
    function construct_ontologies(documents)

        ontologies = initialize_dictionary()
        for (document, document_data) in documents
            m = match(r"^(ISO|IEC) 80000-(\d+)$", document)
            if !isnothing(m)
                for (type, suffix) in ONTOLOGY_TYPES
                    d = initialize_dictionary()
                    d["label"] = "$document:$(document_data["Year"])"
                    source = "$document Quantities and units — Part $(document_data["Part"]): $(document_data["Subject Area"])"
                    d["source"] = source
                    d["type"] = type
                    d["iri_stem"] = "$(lowercase(m[1]))-80000/$(m[2])-$suffix"
                    d["prefix"] = "$(lowercase(m[1]))-80000-$(m[2])-$suffix"
                    d["companion_iri_stem"] = replace(d["iri_stem"], Regex("-$suffix\$") => "-$(ONTOLOGY_COMPANION[suffix])")
                    ontologies["$document $type"] = d
                end
            end
        end
        ontologies
    end

    export construct_bundles
    function construct_bundles(ontologies, stem = "iso-80000", title_stem = "ISO 80000")

        bundles = initialize_dictionary()
        for (type, suffix) in BUNDLE_TYPES
            d = initialize_dictionary()
            d["type"] = type
            d["iri_stem"] = "$stem/$suffix"
            d["prefix"] = "$stem-$suffix"
            bundles["$title_stem $type"] = d
        end
        for (bundle_data) in values(bundles)
            imports = []
            imports_type_list = BUNDLE_IMPORTS[bundle_data["type"]]
            for import_type in imports_type_list
                candidates = collect(Iterators.flatmap(h -> values(h), [bundles, ontologies]))
                append!(imports, map(oh -> oh["iri_stem"], filter(oh -> oh["type"] == import_type, candidates)))
            end
            bundle_data["imports"] = imports
        end
        bundles
    end

    export construct_quantity_instances
    function construct_quantity_instances(quantities, ontologies)
        quantity_instances = initialize_dictionary()
        for (quantity, quantity_data) in quantities
            d = initialize_dictionary()
            d["name"] = quantity
            document = remove_paren_text(quantity_data["Defining Document"])
            ontology_key = "$document description"
            ontology_data = ontologies[ontology_key]
            d["description_iri_stem"] = ontology_data["iri_stem"]
            d["vocabulary_iri_stem"] = ontology_data["companion_iri_stem"]
            d["type"] = quantity_data["Type"]
            d["description"] = quantity_data["Description"]
            d["symbol"] = quantity_data["Symbol"]
            d["dimension_symbol"] = quantity_data["Dimension Symbol"]
            name = instance_name(quantity)
            d["kind_class"] = NamingConventions.convert(SnakeCase, PascalCase, name)
            d["unit_class"] = "$(d["kind_class"])Unit"
            d["value_class"] = "$(d["kind_class"])Value"
            quantity_instances[name] = d
        end
        quantity_instances
    end

    export construct_unit_instances
    function construct_unit_instances(units, quantities, ontologies, quantity_instances)
        unit_instances = initialize_dictionary()
        for (unit, unit_data) in units
            d = initialize_dictionary()
            d["name"] = unit
            document = remove_paren_text(unit_data["Defining Document"])
            ontology_key = "$document description"
            ontology_data = ontologies[ontology_key]
            d["description_iri_stem"] = ontology_data["iri_stem"]
            d["vocabulary_iri_stem"] = ontology_data["companion_iri_stem"]
            d["type"] = unit_data["Type"]
            if d["type"] == "Derived"
                d["expression"] = unit_data["Expressed In Base Units"]
            end
            d["description"] = unit_data["Definition"]
            d["symbol"] = unit_data["Symbol"]
            quantity_string = unit_data["ISQ Quantities"]
            if !ismissing(quantity_string)
                quantity = instance_name(remove_paren_text(quantity_string))
                d["quantity"] = quantity
                d["unit_class"] = NamingConventions.convert(SnakeCase, PascalCase, quantity)
            end
            name = instance_name(unit)
            unit_instances[name] = d
        end
        unit_instances
    end

end
