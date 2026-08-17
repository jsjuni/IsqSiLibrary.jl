module Main

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI
    
    # dc vocabulary

    const DC_CREATOR = "<http://purl.org/dc/elements/1.1/creator>"
    const DC_DESCRIPTION = "<http://purl.org/dc/elements/1.1/description>"
    const DC_SOURCE = "<http://purl.org/dc/elements/1.1/source>"
    const DC_TITLE = "<http://purl.org/dc/elements/1.1/title>"

    # rdf vocabulary

    const RDF_TYPE = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>"

    # rdfs vocabulary

    const RDFS_LABEL = "<http://www.w3.org/2000/01/rdf-schema#label>"

    # vim3 vocabulary

    const IS_PROPERTY_OF = "<http://bipm.org/jcgm/vim3-v#isPropertyOf>"
    const HAS_DIMENSION_SYMBOL = "<http://bipm.org/jcgm/vim3-v#hasDimensionSymbol>"

    # iso 80000 vocabulary

    const HAS_QUANTITY_IDENTIFIER = "<http://iso.org/iso-80000/1-v#hasQuantityIdentifier>"
    const HAS_UNIT_IDENTIFIER = "<http://iso.org/iso-80000/1-v#hasUnitIdentifier>"
    const HAS_SYMBOL = "<http://iso.org/iso-80000/1-v#hasSymbol>"

    const ISQ_BASE_QUANTITY = "<http://iso.org/iso-80000/1-v#ISQBaseQuantity>"
    const ISQ_DERIVED_QUANTITY = "<http://iso.org/iso-80000/1-v#ISQDerivedQuantity>"
    
    const SI_BASE_UNIT = "<http://iso.org/iso-80000/1-v#SIBaseUnit>"
    const SI_DERIVED_UNIT = "<http://iso.org/iso-80000/1-v#SIDerivedUnit>"

    const IS_BASE_UNIT_FOR = "<http://iso.org/iso-80000/1-v#isBaseUnitFor>"
    const IS_DERIVED_UNIT_FOR = "<http://iso.org/iso-80000/1-v#isDerivedUnitFor>"

    #

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

    function create_quantity_or_unit_instance(instance_data, instance_id, namespace_base, has_identifier, base_or_derived, separator)
        operations = []
        (description_iri, description_ns) = ontology_iri_ns(
            namespace_base, instance_data["description_iri_stem"], separator
        )
        instance_iri = description_ns * instance_id
        append!(operations, [
            create_instance(description_iri, instance_id),
            add_assertion(description_iri, instance_iri, RDF_TYPE, base_or_derived),
            add_annotation(description_iri, instance_iri, RDFS_LABEL, instance_data["name"]),
            add_annotation(description_iri, instance_iri, DC_DESCRIPTION, instance_data["description"]),
            add_assertion(description_iri, instance_iri, has_identifier, instance_data["name"]),
            add_assertion(description_iri, instance_iri, HAS_SYMBOL, instance_data["symbol"])
        ])
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
                    add_annotation(ontology_iri, ontology_iri, DC_TITLE, ontology_id),
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
            @info "$(now())   $(unit_data["description_iri_stem"]) $unit_id"

            # create quantity instance

            append!(stage_1,
                create_quantity_or_unit_instance(
                    unit_data,
                    unit_id,
                    namespace_base,
                    HAS_UNIT_IDENTIFIER,
                    unit_data["type"] == "Base" ? SI_BASE_UNIT : SI_DERIVED_UNIT,
                    separator
                )
            )

            # assert unit class of instance
            
            @info "$(now())     assert $unit_id type $(unit_data["unit_class"])"

            # assert "is unit for" relation if appropriate

            if haskey(unit_data, "quantity")
                relation = unit_data["type"] == "Base" ? IS_BASE_UNIT_FOR : IS_DERIVED_UNIT_FOR
                (u_description_iri, u_description_ns) = ontology_iri_ns(
                    namespace_base, unit_data["description_iri_stem"], separator
                )
                quantity_id = unit_data["quantity"]
                quantity_data = input["quantity_instances"][quantity_id]
                (q_description_iri, q_description_ns) = ontology_iri_ns(
                    namespace_base, quantity_data["description_iri_stem"], separator
                )
                unit_iri = u_description_ns * unit_id
                quantity_iri = q_description_ns * quantity_id
                @info "$(now())     assert $unit_id unit for relation to $quantity_id"
                push!(stage_1,
                    add_assertion(u_description_iri, unit_iri, relation, quantity_iri)
                )
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