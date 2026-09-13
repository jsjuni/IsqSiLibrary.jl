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

    export construct_integrations
    function construct_integrations(authorities, ontologies, integrations_df)
        
        integrations = initialize_dictionary()

        for row in eachrow(integrations_df)
            integration_id = row["Integration"]
            integration_path = row["IRI Path"]
            for (type, suffix) in ONTOLOGY_TYPES
                prefix = joinpath(integration_path, suffix)
                d = OrderedDict(
                    "integration" => integration_id,
                    "type" => type,
                    "prefix" => prefix,
                    "iri_path" => prefix
                )
                integrations[prefix] = d
            end
        end

        integrations
    end

    export construct_bundles
    function construct_bundles(authorities, ontologies, integrations, bundles_df)

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
                    push!(d["imports"], joinpath(bundle_path, BUNDLE_TYPES["vocabulary"]))
                end
                bundles[prefix] = d
            end
        end

        for row in eachrow(bundles_df)
            bundle_path = row["IRI Path"]
            imports_integration = get_keys(row["Imports Integration"])
            for (type, suffix) in ONTOLOGY_TYPES
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
                        integration -> integration["integration"] in imports_integration && integration["type"] == type,
                        collect(values(integrations))
                    )
                )
                append!(bundles[importing_prefix]["imports"], imported_iri_paths)
                if type == "description"
                    push!(bundles[importing_prefix]["imports"], joinpath(bundle_path, ONTOLOGY_TYPES["vocabulary"]))
                end
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

            # quantity type (base, derived, etc.) follows from highest unit type

            units = collect(unique(mapfoldl(c -> get_keys(row[c]), append!, ["Units By Symbol", "Units By URI"])))
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

            quantity_labels = append!(get_keys(row["QuantityKindsByURI"]), get_keys(row["QuantityKindsByUnitSymbol"]))
            quantity_dicts = filter(
                qd -> qd["label"] in quantity_labels,
                collect(values(si_quantities))
            )
            quantities = map(
                d -> Dict(d["description_iri_path"] => d["label"]),
                quantity_dicts
            )
            quantity_classes = map(
                d -> Dict(d["vocabulary_iri_path"] => d["classes"]),
                quantity_dicts
            )
 
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
                "symbol" => symbol,
                "iri" => iri,
                "vocabulary_iri_path" => vocabulary["iri_path"],
                "description_iri_path" => description["iri_path"],
                "type" => type,
                "quantities" => quantities,
                "quantity_classes" => quantity_classes
            )

            units[iri] = d
        end

        units
    end

    export construct_isq_quantities
    function construct_isq_quantities(ontologies, si_quantities, si_units, isq_quantities_df,
            isq_alternate_quantity_names_df, isq_quantity_symbols_df, isq_units_df)
        quantities = initialize_dictionary()
        for row in eachrow(isq_quantities_df)

            # look up vocabulary and description info dicts

            document_id = remove_md_link(row["Defining Document"])
            (vocabulary, description) = get_ontologies(document_id, ontologies)

            # set quantity properties and create quantity dict

            label = row["Quantity"]
            name = NamingConventions.convert(SpaceCase, SnakeCase, label)
            source = row["Item"]
            iri = "$(vocabulary["iri_path"])#$name"
            classes = OrderedDict()
            for (k, v) in QUANTITY_CLASSES
                classes[k] = NamingConventions.convert(SpaceCase, PascalCase, strip("$label $v"))
            end
            alternate_names = map(
                r -> r["Alternate Name"],
                filter(
                    r -> label in get_keys(r["Derived Quantity"]),
                    eachrow(isq_alternate_quantity_names_df)
                )
            )
            symbols = map(
                r -> r["LaTeX"],
                filter(
                    r -> label in get_keys(r["📐 ISQ Quantities"]),
                    eachrow(isq_quantity_symbols_df)
                )
            )
            related_si_qty_label = row["Related SI Quantity"]
            related_si_quantity = if ismissing(related_si_qty_label)
                    nothing
                else
                    first(map(
                    h -> h["iri"],
                        filter(
                            d -> d["label"] == remove_md_link(row["Related SI Quantity"]),
                            collect(values(si_quantities))
                        )
                    ))
                end
            d = OrderedDict(
                "label" => label,
                "name" => name,
                "source" => source,
                "iri" => iri,
                "vocabulary_iri_path" => vocabulary["iri_path"],
                "description_iri_path" => description["iri_path"],
                "classes" => classes,
                "alternate_names" => alternate_names,
                "symbols" => symbols,
                "related_si_quantity" => related_si_quantity
            )

            # save quantity dict

            quantities[iri] = d
        
        end

        quantities
    end

    export construct_isq_units
    function construct_isq_units(ontologies, si_quantities, si_units, isq_quantities, isq_units_df)
        units = initialize_dictionary()
        for row in eachrow(isq_units_df)

            label = row["Unit"]
            quantity_dicts = filter(
                d -> d["label"] in get_keys(row["ISQ Quantities"]),
                collect(values(isq_quantities))
            )
            ontology_map = foldl(
                function(ad, qd)
                    d_iri_path = qd["description_iri_path"]
                    v_iri_path = qd["vocabulary_iri_path"]
                    if !haskey(ad, d_iri_path)
                        ad[d_iri_path] = Dict("quantities" => [], "classes" => Dict())
                    end
                    push!(ad[d_iri_path]["quantities"], qd["label"])
                    if !haskey(ad[d_iri_path]["classes"], v_iri_path)
                        ad[d_iri_path]["classes"][v_iri_path] = []
                    end
                    push!(ad[d_iri_path]["classes"][v_iri_path], qd["classes"]["unit"])
                    ad
                end,
                quantity_dicts,
                init = Dict()
            )

            # set unit properties and create unit dict

            name = NamingConventions.convert(SpaceCase, SnakeCase, label)
            symbol = row["Symbol"]
            for (description_iri_path, ontology_dict) in ontology_map
                iri = "$(description_iri_path)#$name"
                d = OrderedDict(
                    "label" => label,
                    "name" => name,
                    "symbol" => symbol,
                    "iri" => iri,
                    "description_iri_path" => description_iri_path,
                    "quantities" => ontology_dict["quantities"],
                    "quantity_classes" => ontology_dict["classes"]
                )

                units[iri] = d
            end
        end

        units
    end

    export reconcile_isq_units
    function reconcile_isq_units(isq_units)
        reconciliation = initialize_dictionary()

        for (unit_id, unit_data) in isq_units
            unit_class = NamingConventions.convert(SpaceCase, PascalCase, unit_data["label"])
            description_iri_path = unit_data["description_iri_path"]
            ruc = if haskey(reconciliation, unit_class)
                reconciliation[unit_class]
            else
                reconciliation[unit_class] = Dict("instances" => Dict(), "classes" => Dict())
            end

            ruci = ruc["instances"]
            ilist = if haskey(ruci, description_iri_path)
                ruci[description_iri_path]
            else
                ruci[description_iri_path] = []
            end
            push!(ilist, unit_data["name"])

            rucc = ruc["classes"]
            for (vocabulary_iri_path, unit_classes) in unit_data["quantity_classes"]
                clist = if haskey(rucc, vocabulary_iri_path)
                    rucc[vocabulary_iri_path]
                else
                    rucc[vocabulary_iri_path] = []
                end
                append!(clist, unit_classes)
            end
        end

        filter(
            p -> (
                mapreduce(
                    v -> length(v),
                    +,
                    values(last(p)["classes"])
                ) > 1
            ) || (
                mapreduce(
                v -> length(v),
                +,
                values(last(p)["instances"])
                ) > 1
            ),
            reconciliation
        )
    end

end
