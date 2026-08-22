module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI
    
    const PLURAL = Dict("quantity" => "quantities", "unit" => "units", "value" => "values")

    function parse_commandline()
        s = ArgParseSettings()
        @add_arg_table s begin
            "--input"
                help = "path prefix to input JSON"
                arg_type = String
                required = true
            "--server"
                help = "Column name for server URL (default: http://127.0.0.1:8080)"
                arg_type = String
                default = "http://127.0.0.1:8080"
            "--path-base"
                help = "OML source path base (default: src/oml/model)"
                arg_type = String
                default = "src/model/oml"
            "--namespace-base"
                help = "Base namespace for OML (default: http://studioj.us/mass-props-oml)"
                arg_type = String
                default = "http://studioj.us/mass-props-oml"
            "--separator"
                help = "Namespace separator (default: #)"
                arg_type = String
                default = "#"
            "--defer-diagnostics"
                help = "Defer diagnostics until the end (default: false)"
                action = :store_true
            "--inhibit-updates"
                help = "Inhibit updates to server (default: false)"
                action = :store_true
            "--creator"
                help = "Value of dc:creator annotation on ontologies and bundles"
                arg_type = String
                default = nothing
        end
        return parse_args(s)
    end

    function ontology_iri_ns(base, stem, separator)
        iri = joinpath(base, stem)
        ns = iri * separator
        (iri, ns)
    end

    function create_quantity_or_unit_instance(instance_data, description_iri_stem, instance_id, namespace_base, has_identifier, base_or_derived, separator)
        operations = []
        (description_iri, description_ns) = ontology_iri_ns(
            namespace_base, description_iri_stem, separator
        )
        instance_iri = description_ns * instance_id
        append!(operations, [
            create_instance(description_iri, instance_id),
            add_assertion(description_iri, instance_iri, RDF_TYPE, base_or_derived),
            add_annotation(description_iri, instance_iri, RDFS_LABEL, instance_data["name"]),
            add_assertion(description_iri, instance_iri, has_identifier, instance_data["name"]),
        ])

        if haskey(instance_data, "symbols")
            for symbol in instance_data["symbols"]
                push!(operations,
                    add_assertion(description_iri, instance_iri, HAS_SYMBOL, symbol)
                )
            end
        end
    
        if haskey(instance_data, "alternate_names")
            for alternate_name in instance_data["alternate_names"]
                push!(operations,
                    add_annotation(description_iri, instance_iri, RDFS_LABEL, alternate_name)
                )
            end
        end
        operations
    end

    function capitalize(string)
        Base.Unicode.uppercasefirst(string)
    end

    function(@main)(ARGS)

        @info "$(now()) start"
        @info "$(now()) parse command arguments"
        args = parse_commandline()

        # shorter names

        namespace_base = args["namespace-base"]
        namespace_path = replace(namespace_base, r".*//" => "")
        path_base = args["path-base"]
        separator = args["separator"]
        creator = args["creator"]

        # check server status

        server = args["server"]
        @info "$(now()) check server status at $server"
        if !is_alive(server)
            @error "Server is not alive at " args["server"]
            exit(1)
        end

        # load input

        input_filename = args["input"]
        @info "$(now()) load input from $input_filename"
        input_file = open(input_filename, "r")

        input = JSON.parse(input_file)

        stage_1 = []
        stage_2 = []

        operations = OrderedDict(
            "stage 1" => stage_1,
            "stage 2" => stage_2
        )

        # create ontologies

        @info "$(now()) create ontologies"
        for (ontology_id, ontology_data) in input["ontologies"]
            filename = joinpath(path_base, namespace_path, ontology_data["iri_stem"]) * ".oml"
            if isfile(filename)
                @info "$(now())   skip $ontology_id: file exists"
            else
                (ontology_iri, ontology_namespace) = ontology_iri_ns(namespace_base, ontology_data["iri_stem"], args["separator"])
                @info "$(now())   create $ontology_id $ontology_namespace"
                append!(stage_1, [
                    create_ontology(
                        ontology_data["type"],
                        ontology_namespace,
                        ontology_data["prefix"],
                        args["path-base"]
                    ),
                    add_annotation(ontology_iri, ontology_iri, IsqSiLibrary.DC_TITLE, ontology_id),
                    add_annotation(ontology_iri, ontology_iri, RDFS_LABEL, ontology_data["label"]),
                    add_annotation(ontology_iri, ontology_iri, DC_SOURCE, ontology_data["source"])
                ])
                if !isnothing(creator)
                    push!(stage_1, add_annotation(ontology_iri, ontology_iri, DC_CREATOR, creator))
                end
            end
        end

        # create bundles

        @info "$(now()) create bundles"
        for (bundle_id, bundle_data) in input["bundles"]
            (bundle_iri, bundle_namespace) = ontology_iri_ns(namespace_base, bundle_data["iri_stem"], args["separator"])
            @info "$(now())   create $bundle_id $bundle_namespace"
            append!(stage_1, [
                create_ontology(
                    bundle_data["type"],
                    bundle_namespace,
                    bundle_data["prefix"],
                    args["path-base"]
                ),
                add_annotation(bundle_iri, bundle_iri, DC_TITLE, bundle_id)
            ])
            if !isnothing(creator)
                push!(stage_1, add_annotation(bundle_iri, bundle_iri, DC_CREATOR, creator))
            end
            if bundle_data["type"] == "vocabulary bundle"
                push!(stage_2, add_import(bundle_iri, VIM3_VOCABULARY))
            else
                push!(stage_2, add_import(bundle_iri, VIM3_VOCABULARY))
                push!(stage_2, add_import(bundle_iri, VIM3_DESCRIPTION))
            end
            for imprt in bundle_data["imports"]
                (imprt_iri, unused) = ontology_iri_ns(namespace_base, imprt, args["separator"])
                @info "$(now())     add import for $imprt"
                push!(stage_2, add_import(bundle_iri, imprt_iri))
            end
        end

        # process quantities

        @info "$(now()) process quantities"
        for (quantity_id, quantity_data) in input["quantity_instances"]
            @info "$(now())   $(quantity_data["description_iri_stem"]) $quantity_id"

            # create quantity instance

            append!(stage_1,
                create_quantity_or_unit_instance(
                    quantity_data,
                    quantity_data["description_iri_stem"],
                    quantity_id,
                    namespace_base,
                    HAS_QUANTITY_IDENTIFIER,
                    quantity_data["type"] == "Base" ? ISQ_BASE_QUANTITY : ISQ_DERIVED_QUANTITY,
                    separator
                )
            )

            (vocabulary_iri, vocabulary_ns) = ontology_iri_ns(
                namespace_base, quantity_data["vocabulary_iri_stem"], separator
            )
            (description_iri, description_ns) = ontology_iri_ns(
                namespace_base, quantity_data["description_iri_stem"], separator
            )
            quantity_iri = description_ns * quantity_id

            # add identifier annotation and description

            append!(stage_1, [
                add_annotation(description_iri, quantity_iri, DC_IDENTIFIER, quantity_data["item"]),
                add_annotation(description_iri, quantity_iri, DC_DESCRIPTION, quantity_data["description"])
            ])

            # create quantity classes

            for category_key in ("quantity", "unit", "value")
                concept = quantity_data["$(category_key)_class"]
                description = "$(capitalize(PLURAL[category_key])) of quantity kind \"$(quantity_data["name"])\"."
                @info "$(now())     create concept $vocabulary_ns$concept"
                @info "$(now())       description: $description"
                append!(stage_1, [
                ])
            end

            # assert dimension symbol

            push!(stage_1,
                add_assertion(description_iri, quantity_iri, HAS_DIMENSION_SYMBOL, quantity_data["dimension_symbol"])
            )

            # assert quantity class of instance

            @info "$(now())     assert $quantity_id type $(quantity_data["quantity_class"])"

            # create quantity relation

            @info "$(now())     create forward relation $vocabulary_ns$(quantity_data["relation"]["forward"])"
            @info "$(now())            reverse relation $vocabulary_ns$(quantity_data["relation"]["reverse"])"
            append!(stage_1, [
            ])

       end

        # process units

        @info "$(now()) process units"
        for (unit_id, unit_data) in input["unit_instances"]
            continue # skip for now
            for description_iri_stem = unit_data["description_iri_stem"]
                @info "$(now())   $(description_iri_stem) $unit_id"

                # create quantity instance

                append!(stage_1,
                    create_quantity_or_unit_instance(
                        unit_data,
                        description_iri_stem,
                        unit_id,
                        namespace_base,
                        HAS_UNIT_IDENTIFIER,
                        unit_data["type"] == "Base" ? SI_BASE_UNIT : SI_DERIVED_UNIT,
                        separator
                    )
                )

                (description_iri, description_ns) = ontology_iri_ns(
                    namespace_base, description_iri_stem, separator
                )
                unit_iri = description_ns * unit_id

                # assert unit classes of instance
                
                vocabulary_iri_stem = companion_iri_stem(description_iri_stem, input["ontologies"])

                for quantity in unit_data["quantity"]
                    quantity_data = input["quantity_instances"][quantity]
                    if vocabulary_iri_stem == quantity_data["vocabulary_iri_stem"]
                        (vocabulary_iri, vocabulary_ns) = ontology_iri_ns(
                            namespace_base, vocabulary_iri_stem, separator)
                        unit_class = Dict(
                            "datatypeIri" => XSD_ANYURI,
                            "value" => vocabulary_iri * quantity_data["unit_class"]
                        )
                    
                        @info "$(now())     assert $unit_id type $(quantity_data["unit_class"])"
                        push!(stage_1,
                            add_annotation(description_iri, unit_iri, DC_TYPE, unit_class)
                        )
                    end
                end

                # assert base unit expression for derived units

                if unit_data["type"] != "Base" # some "Supplemental" and "Jenkins" junk in there
                    push!(stage_1,
                        add_assertion(description_iri, unit_iri, HAS_BASE_UNIT_EXPRESSION, unit_data["expression"])
                    )
                end
            end
        end

        # update server

        if args["inhibit-updates"]
            @info "$(now()) server updates inhibited"
        else
            @info "$(now()) update server"
            for (name, ops) in operations
                @info "$(now())   $name $(length(ops)) operations"
                update(server, ops, args["defer-diagnostics"])
            end
        end

        # end

        @info "$(now()) end"

    end

end