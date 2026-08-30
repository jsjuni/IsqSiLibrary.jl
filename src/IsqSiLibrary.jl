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
        "vocabulary" => "vb",
        "description" => "db"
    )
    
    const BUNDLE_IMPORTS = Dict(
        "vocabulary" => [],
        "description" => ["vocabulary"]
    )

    const BASE_UNITS = Dict(
        "T" => "s",
        "L" => "m",
        "M" => "kg",
        "I" => "A",
        "Θ" => "K",
        "N" => "mol",
        "J" => "cd"
    )

    const QUANTITY_CLASSES = OrderedDict(
        "quantity" => "",
        "unit" => "unit",
        "value" => "value"
    )

    const SI_UNIT_TYPES = Dict{Union{Missing, Nothing, String},Union{Nothing, String}}(
        "SI base unit" => "base",
        "Named SI derived unit" => "named",
        "Non-SI unit accepted for use with the SI" => "non-si",
        missing => nothing,
        nothing => nothing
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

    function remove_md_link(string)
        replace(string, r" \(\S+\.md\)$" => "")
    end

    function get_keys(string)
        if ismissing(string) || isnothing(string)
            []
        else
            map(remove_md_link, split(string, r"\s*,\s*"))
        end
    end

    function base_expression(dim_string)
        replace(
            foldl((s, (dim, unit)) -> replace(s, dim => unit), BASE_UNITS, init = dim_string),
            r"\s+" => "·"
        )
    end

    function companion_iri_stem(stem, ontologies)
        for ontology in values(ontologies)
            if stem == ontology["iri_stem"]
                return ontology["companion_iri_stem"]
            end
        end
        return nothing
    end

    function get_ontologies(document_id, ontologies)
        map(
            type -> first(filter(
                o -> o["id"] == document_id && o["type"] == type,
                collect(values(ontologies))
            ))
        , ["vocabulary", "description"]
        )
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

    export construct_dimensions
    function construct_dimensions(dimensions)
        dimensions = initialize_dictionary()
        dimensions
    end

    export construct_authorities
    function construct_authorities(authorities_df)
        authorities = initialize_dictionary()
        for row in eachrow(authorities_df)
            authorities[row["Authority"]] = Dict(
                "iri_path" => row["IRI Path"]
            )
        end
        authorities
    end

    export construct_ontologies
    function construct_ontologies(authorities, documents_df)

        ontologies = initialize_dictionary()

        for row in eachrow(documents_df)
            document_id = row["Document"]
            authority = remove_md_link(row["Authority"])
            authority_path = authorities[authority]["iri_path"]
            document_path = ismissing(row["IRI Path"]) ? "" : row["IRI Path"]
            document_stem = string(row["IRI Stem"])
            for (type, suffix) in ONTOLOGY_TYPES
                prefix = replace("$document_path-$document_stem-$suffix", r"^-" => "")
                companion_prefix = "$document_path-$document_stem-$(ONTOLOGY_COMPANION[suffix])"
                iri_path = joinpath(authority_path, document_path, document_stem)
                d = OrderedDict(
                    "id" => document_id,
                    "label" => "$document_id:$(row["Year"])",
                    "title" => row["Title"],
                    "type" => type,
                    "iri_path" => "$iri_path-$suffix",
                    "prefix" => prefix,
                    "companion_prefix" => companion_prefix,
                    "curated" => row["Curated Ontology"] == "Yes"
                )
                ontologies[prefix] = d
            end
        end

        ontologies
    end

    export construct_bundles
    function construct_bundles(authorities, ontologies, bundles_df)

        bundles = initialize_dictionary()

        for row in eachrow(bundles_df)
            bundle_id = row["Bundle"]
            bundle_path = row["IRI Path"]
            imports_ontology = get_keys(row["Imports Ontology"])
            for (type, suffix) in BUNDLE_TYPES
                prefix = "$bundle_path-$suffix"
                d = OrderedDict(
                    "bundle" => bundle_id,
                    "type" => type,
                    "prefix" => prefix,
                    "iri_path" => joinpath(bundle_path, suffix),
                    "imports" => map(
                        o -> o["iri_path"],
                        filter(
                            o -> o["id"] in imports_ontology && o["type"] == type,
                            collect(values(ontologies))
                        )
                    )
                )
                if type == "description"
                    push!(d["imports"], replace(prefix, r"-db$" => "-vb"))
                end
                bundles[prefix] = d
            end

        end

        for row in eachrow(bundles_df)
            imports_bundle = get_keys(row["Imports Bundle"])
            for (type, suffix) in BUNDLE_TYPES
                importing_prefix = first(map(
                    ib -> ib["prefix"],
                    filter(
                        bundle -> bundle["bundle"] == row["Bundle"] && bundle["type"] == type,
                        collect(values(bundles))
                    )
                ))
                imported_iri_paths = map(
                    ib -> ib["iri_path"],
                    filter(
                        bundle -> bundle["bundle"] in imports_bundle && bundle["type"] == type,
                        collect(values(bundles))
                    )
                )
                append!(bundles[importing_prefix]["imports"], imported_iri_paths)
            end
        end

        bundles
    end

    export construct_si_quantities
    function construct_si_quantities(ontologies, si_quantities_df, si_units_df)
        quantities = initialize_dictionary()

        for row in eachrow(si_quantities_df)

            # quantities for named units only

            if row["Anonymous Unit"] == "Yes"
                continue
            end

            # quantity type (base, derived, etc.) follows from highest unit type
            # omit Units by Symbol
            # we may not need this

            units = collect(unique(mapfoldl(c -> get_keys(row[c]), append!, ["Units By URI"])))
            if isempty(units)
                continue
            end
            unit_types = map(u -> SI_UNIT_TYPES[u], si_units_df[in.(si_units_df.Unit, [units]), :Type])
            type = if any(unit_types .== "base")
                "base"
            elseif any(unit_types .== "named")
                "named"
            elseif any(unit_types .== "non-si")
                "non-si"
            else
                nothing
            end

            # look up vocabulary and description info dicts

            document_id = remove_md_link(row["Defining Documents"])
            (vocabulary, description) = get_ontologies(document_id, ontologies)

            # set quantity properties and create quantity dict

            label = row["Quantity"]
            name = NamingConventions.convert(SpaceCase, SnakeCase, label)
            iri = "$(vocabulary["iri_path"])#$name"
            classes = OrderedDict()
            for (k, v) in QUANTITY_CLASSES
                classes[k] = NamingConventions.convert(SpaceCase, PascalCase, strip("$label $v"))
            end
            d = OrderedDict(
                "label" => label,
                "si_label" => row["Label"],
                "name" => name,
                "iri" => iri,
                "vocabulary_iri_path" => vocabulary["iri_path"],
                "description_iri_path" => description["iri_path"],
                "classes" => classes,
                "type" => type
            )

            # save quantity dict

            quantities[iri] = d
        end

        quantities
    end

    export construct_si_units
    function construct_si_units(ontologies, si_quantities, si_units_df)
        units = initialize_dictionary()

        for row in eachrow(si_units_df)

            quantity_label = remove_md_link(row["QuantityKindsByURI"])
            quantity_dict = first(filter(
                qd -> qd["label"] == quantity_label,
                collect(values(si_quantities))
            ))
            quantity_class = quantity_dict["classes"]["quantity"]
 
            document_id = remove_md_link(row["Defining Documents"])
            (vocabulary, description) = get_ontologies(document_id, ontologies)

            # set unit properties and create unit dict

            label = row["Unit"]
            name = NamingConventions.convert(SpaceCase, SnakeCase, label)
            symbol = row["Symbol"]
            iri = "$(vocabulary["iri_path"])#$name"
            type = SI_UNIT_TYPES[row["Type"]]
            d = OrderedDict(
                "label" => label,
                "name" => name,
                "symmbol" => symbol,
                "iri" => iri,
                "vocabulary_iri_path" => vocabulary["iri_path"],
                "description_iri_path" => description["iri_path"],
                "type" => type,
                "class" => quantity_class
            )

            units[iri] = d
        end

        units
    end

    export construct_isq_entities
    function construct_isq_entities(ontologies, si_quantities_df, si_units_df, isq_quantities_df, isq_units_df)
        entities = initialize_dictionary()
    end

    export construct_quantity_instances
    function construct_quantity_instances(quantities, ontologies, symbols)
        quantity_instances = initialize_dictionary()
        for (quantity, quantity_data) in quantities
            d = initialize_dictionary()
            d["name"] = quantity
            alternate_names = quantity_data["Alternate Names"]
            d["alternate_names"] = ismissing(alternate_names) ? [] : map(remove_md_link, split(alternate_names, r"\s*,\s*"))
            document = remove_md_link(quantity_data["Defining Document"])
            ontology_key = "$document description"
            ontology_data = ontologies[ontology_key]
            d["description_iri_stem"] = ontology_data["iri_stem"]
            d["vocabulary_iri_stem"] = ontology_data["companion_iri_stem"]
            d["type"] = quantity_data["Type"]
            d["item"] = quantity_data["Item"]
            d["description"] = quantity_data["Description"]
            symbol_field = quantity_data["Symbol"]
            symbol_keys = ismissing(symbol_field) ? [] : map(remove_md_link, split(symbol_field, r"\s*,\s*"))
            d["symbols"] = map(k -> symbols[k]["LaTeX"], symbol_keys)
            d["dimension_symbol"] = "[to be constructed]"
            name = instance_name(quantity)
            d["quantity_class"] = NamingConventions.convert(SnakeCase, PascalCase, name)
            d["unit_class"] = "$(d["quantity_class"])Unit"
            d["value_class"] = "$(d["quantity_class"])Value"
            d["relation"] = OrderedDict(
                "forward" => "is$(d["quantity_class"])Of",
                "reverse" => "has$(d["quantity_class"])"
            )
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
            d["type"] = unit_data["Type"]
            if d["type"] == "Derived"
                d["expression"] = unit_data["Expressed In Base Units"]
            end
            d["symbol"] = unit_data["Symbol"]
            quantity_string = unit_data["ISQ Quantities"]
            if !ismissing(quantity_string)
                qs = map(remove_md_link, split(quantity_string, r"\s*,\s*"))
                d["quantity"] = map(
                    function(q)
                        NamingConventions.convert(SpaceCase, SnakeCase, q)
                    end,
                    qs
                )
                d["description_iri_stem"] = unique(map(
                    function(q)
                        quantity_data = quantity_instances[q]
                        quantity_data["description_iri_stem"]
                    end,
                    d["quantity"]
                ))
            end
            name = instance_name(unit)
            unit_instances[name] = d
        end
        unit_instances
    end

end
