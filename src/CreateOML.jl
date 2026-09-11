module CreateOML

    using ArgParse
    using Logging
    using Dates
    using IsqSiLibrary
    using JSON
    using OrderedCollections
    using OMLCodeAPI
    
    # xsd vocabulary

    const XSD_ANYURI = "<http://www.w3.org/2001/XMLSchema#anyURI>"
    
    # dc vocabulary

    const DC_CREATOR = "<http://purl.org/dc/elements/1.1/creator>"
    const DC_DESCRIPTION = "<http://purl.org/dc/elements/1.1/description>"
    const DC_SOURCE = "<http://purl.org/dc/elements/1.1/source>"
    const DC_TITLE = "<http://purl.org/dc/elements/1.1/title>"
    const DC_IDENTIFIER = "<http://purl.org/dc/elements/1.1/identifier>"
    const DC_TYPE = "<http://purl.org/dc/elements/1.1/type>"

    # rdf vocabulary

    const RDF_TYPE = "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>"

    # rdfs vocabulary

    const RDFS_LABEL = "<http://www.w3.org/2000/01/rdf-schema#label>"
    const RDFS_COMMENT = "<http://www.w3.org/2000/01/rdf-schema#comment>"

    # vim vocabulary

    const HAS_QUANTITY_IDENTIFIER = "<http://bipm.org/vim-v#hasQuantityIdentifier>"
    const HAS_MEASUREMENT_UNIT_IDENTIFIER = "<http://bipm.org/vim-v#hasMeasurementUnitIdentifier>"

    const IS_MEASUREMENT_UNIT_FOR = "<http://bipm.org/vim-v#isMeasurementUnitFor>"
    const IS_PROPERTY_OF = "<http://bipm.org/vim-v#isPropertyOf>"
    const HAS_DIMENSION_SYMBOL = "<http://bipm.org/vim-v#hasDimensionSymbol>"

    const SI_QUANTITY = "<http://bipm.org/si-prov-v#SIQuantity>"
    const SI_BASE_QUANTITY = "<http://bipm.org/si-prov-v#SIBaseQuantity>"
    const SI_NAMED_QUANTITY = "<http://bipm.org/si-prov-v#SINamedQuantity>"
    const SI_NON_SI_QUANTITY = "<http://bipm.org/si-prov-v#SINonSIQuantity>"
 
    const SI_UNIT = "<http://bipm.org/si-prov-v#SIUnit>"
    const SI_BASE_UNIT = "<http://bipm.org/si-prov-v#SIBaseUnit>"
    const SI_NAMED_UNIT = "<http://bipm.org/si-prov-v#SINamedUnit>"
    const SI_NON_SI_UNIT = "<http://bipm.org/si-prov-v#SINonSIUnit>"

    const HAS_UNIT_SYMBOL = "<http://bipm.org/si-prov-v#hasUnitSymbol>"

    # iso 80000 vocabulary

    const HAS_SYMBOL = "<http://iso-iec/iso.org/iso-80000/1-v#hasSymbol>"

    const ISQ_BASE_QUANTITY = "<http://iso-iec/iso.org/iso-80000/1-v#ISQBaseQuantity>"
    const ISQ_DERIVED_QUANTITY = "<http://iso-iec/iso.org/iso-80000/1-v#ISQDerivedQuantity>"
    
    const IS_BASE_UNIT_FOR = "<http://iso-iec/iso.org/iso-80000/1-v#isBaseUnitFor>"
    const IS_DERIVED_UNIT_FOR = "<http://iso-iec/iso.org/iso-80000/1-v#isDerivedUnitFor>"

    const HAS_BASE_UNIT_EXPRESSION = "<http://iso-iec/iso.org/iso-80000/1-v#hasBaseUnitExpression>"

    # other constants

    const PLURAL = Dict("quantity" => "quantities", "unit" => "units", "value" => "values")

    const SI_QUANTITY_CLASS = Dict(
        "base" => SI_BASE_QUANTITY,
        "named" => SI_NAMED_QUANTITY,
        "non-si" => SI_NON_SI_QUANTITY,
        missing => SI_QUANTITY,
        nothing => SI_QUANTITY
    )

    const SI_UNIT_CLASS = Dict(
        "base" => SI_BASE_UNIT,
        "named" => SI_NAMED_UNIT,
        "non-si" => SI_NON_SI_UNIT,
        missing => SI_UNIT,
        nothing => SI_UNIT
    )

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
            "--partition-size"
                help = "Parition size for segmented updates"
                arg_type = Int64
                default = 100
            "--save-operations"
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

    function capitalize(string)
        Base.Unicode.uppercasefirst(string)
    end

    export main
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

        global_logger(ConsoleLogger(Info))

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

        stage_1 = [] # bundle deletion
        stage_2 = [] # ontology deletion
        stage_3 = [] # ontology and bundle creation, population
        stage_4 = [] # bundle imports

        operations = OrderedDict(
            "stage 1" => stage_1,
            "stage 2" => stage_2,
            "stage 3" => stage_3,
            "stage 4" => stage_4
        )

        # create ontologies

        @info "$(now()) create ontologies"
        for (ontology_id, ontology_data) in input["ontologies"]
            if ontology_data["curated"]
                @info "$(now())   skip curated ontology $ontology_id"
            else
                @info "$(now())   $ontology_id"
                (iri, ns) = ontology_iri_ns(namespace_base, ontology_data["iri_path"], separator)
                label = ontology_data["label"]
                source = "$label $(ontology_data["title"])"
                append!(stage_3, [
                    create_ontology(
                        ontology_data["type"],
                        ns,
                        ontology_data["prefix"],
                        args["path-base"]
                    ),
                    add_annotation(iri, iri, DC_TITLE, ontology_id),
                    add_annotation(iri, iri, RDFS_LABEL, label),
                    add_annotation(iri, iri, DC_SOURCE, source)
                ])
                if !isnothing(creator)
                    push!(stage_3, add_annotation(iri, iri, DC_CREATOR, creator))
                end
            end
        end

        # create bundles

        @info "$(now()) create bundles"
        for (bundle_id, bundle_data) in input["bundles"]
            @info "$(now())   $bundle_id"
            (iri, ns) = ontology_iri_ns(namespace_base, bundle_data["iri_path"], separator)
            type = "$(bundle_data["type"]) bundle"
            append!(stage_3, [
                create_ontology(
                    type,
                    ns,
                    bundle_data["prefix"],
                    args["path-base"]
                ),
                add_annotation(iri, iri, DC_TITLE, bundle_id)
            ])
            if !isnothing(creator)
                push!(stage_3, add_annotation(iri, iri, DC_CREATOR, creator))
            end
            for imported in bundle_data["imports"]
                imported_iri = first(ontology_iri_ns(namespace_base, imported, separator))
                @info "$(now())     imports $imported_iri"
                push!(stage_4, add_import(iri, imported_iri))
            end
        end

        # process si quantities

        @info "$(now()) process si quantities"
        for (quantity_id, quantity_data) in input["si_quantities"]
            label = quantity_data["label"]
            @info "$(now())   $label"
            si_label = quantity_data["si_label"]
            description_iri = first(ontology_iri_ns(namespace_base, quantity_data["description_iri_path"], separator))
            quantity_stem = encode_instance_stem(label)
            quantity_iri = description_iri * separator * quantity_stem
            quantity_class = quantity_data["classes"]["quantity"]
            si_quantity_class = SI_QUANTITY_CLASS[quantity_data["type"]]
            append!(stage_3, [
                create_instance(description_iri, quantity_stem),
                add_annotation(description_iri, quantity_iri, RDFS_LABEL, label),
                add_assertion(description_iri, quantity_iri, HAS_QUANTITY_IDENTIFIER, label),
                add_annotation(description_iri, quantity_iri, RDFS_COMMENT, "type: $quantity_class"),
                add_assertion(description_iri, quantity_iri, RDF_TYPE, si_quantity_class)
            ])
            if !isnothing(si_label)
                push!(stage_3, add_annotation(description_iri, quantity_iri, RDFS_LABEL, si_label))
            end
        end

        # process si units

        @info "$(now()) process si units"
        for (unit_id, unit_data) in input["si_units"]
            label = unit_data["label"]
            @info "$(now())   $label"
            description_iri = first(ontology_iri_ns(namespace_base, unit_data["description_iri_path"], separator))
            unit_stem = encode_instance_stem(label)
            unit_iri = description_iri * separator * unit_stem
            si_unit_class = SI_UNIT_CLASS[unit_data["type"]]
            symbol = unit_data["symbol"]
            append!(stage_3, [
                create_instance(description_iri, unit_stem),
                add_annotation(description_iri, unit_iri, RDFS_LABEL, label),
                add_assertion(description_iri, unit_iri, HAS_MEASUREMENT_UNIT_IDENTIFIER, label),
                add_assertion(description_iri, unit_iri, RDF_TYPE, si_unit_class),
                add_assertion(description_iri, unit_iri, HAS_UNIT_SYMBOL, symbol)
            ])
            for qd in unit_data["quantities"]
                for (qd_iri_path, q_label) in qd
                    qd_iri = first(ontology_iri_ns(namespace_base, qd_iri_path, separator))
                    quantity_stem = encode_instance_stem(q_label)
                    quantity_iri = qd_iri * separator * quantity_stem
                    push!(stage_3, add_assertion(description_iri, unit_iri, IS_MEASUREMENT_UNIT_FOR, quantity_iri))
                end
            end
        end

        # process isq quantities

        @info "$(now()) process isq quantities"
        for (quantity_id, quantity_data) in input["isq_quantities"]
            label = quantity_data["label"]
            @info "$(now())   $label"
            description_iri = first(ontology_iri_ns(namespace_base, quantity_data["description_iri_path"], separator))
            quantity_stem = encode_instance_stem(label)
            quantity_iri = description_iri * separator * quantity_stem
            quantity_class = quantity_data["classes"]["quantity"]
            append!(stage_3, [
                create_instance(description_iri, quantity_stem),
                add_assertion(description_iri, quantity_iri, RDF_TYPE, SI_QUANTITY), # TEMPORARY
                add_annotation(description_iri, quantity_iri, RDFS_LABEL, label),
                add_assertion(description_iri, quantity_iri, HAS_QUANTITY_IDENTIFIER, label),
                add_annotation(description_iri, quantity_iri, RDFS_COMMENT, "type: $quantity_class")
            ])
            append!(stage_3,
                map(
                    s -> add_assertion(description_iri, quantity_iri, HAS_SYMBOL, s),
                    quantity_data["symbols"]
                )
            )
            append!(stage_3,
                map(
                    n -> add_annotation(description_iri, quantity_iri, RDFS_LABEL, n),
                    quantity_data["alternate_names"]
                )
            )
        end
        
        # process isq units

        @info "$(now()) process isq units"
        for (unit_id, unit_data) in input["isq_units"]
            label = unit_data["label"]
            @info "$(now())   $label"
            description_iri = first(ontology_iri_ns(namespace_base, unit_data["description_iri_path"], separator))
            unit_stem = encode_instance_stem(label)
            unit_iri = description_iri * separator * unit_stem
            symbol = unit_data["symbol"]
            append!(stage_3, [
                create_instance(description_iri, unit_stem),
                add_assertion(description_iri, unit_iri, RDF_TYPE, SI_UNIT), # TEMPORARY
                add_annotation(description_iri, unit_iri, RDFS_LABEL, label),
                add_assertion(description_iri, unit_iri, HAS_MEASUREMENT_UNIT_IDENTIFIER, label)
            ])
            if !isnothing(symbol)
                push!(stage_3, add_assertion(description_iri, unit_iri, HAS_UNIT_SYMBOL, symbol))
            end
            for quantity_label = unit_data["quantities"]
                quantity_stem = encode_instance_stem(quantity_label)
                quantity_iri = description_iri * separator * quantity_stem
                push!(stage_3, add_assertion(description_iri, unit_iri, IS_MEASUREMENT_UNIT_FOR, quantity_iri))
            end
            for classes in values(unit_data["quantity_classes"])
                for class in classes
                    push!(stage_3, add_annotation(description_iri, unit_iri, RDFS_COMMENT, "type: $class"))
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
                for set in Iterators.partition(ops, args["partition-size"])
                    @debug "$(now())     updating server with $(length(set)) operations"
                    update(server, set, args["defer-diagnostics"])
                end
            end
        end

        # save operations if requested

        operations_filename = args["save-operations"]
        if !isnothing(args["save-operations"])
            @info "$(now()) save operations to $operations_filename"
            operations_file = open(operations_filename, "w")
            operations = Dict("stage_1" => stage_1, "stage_2" => stage_2, "stage_3" => stage_3, "stage_4" => stage_4)
            JSON.json(operations_file, operations, pretty = true)
        end

        # end

        @info "$(now()) end"

    end

end
using .CreateOML