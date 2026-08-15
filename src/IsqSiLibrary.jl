module IsqSiLibrary

    using CSV
 
    export parse_csv_source
    
    function parse_csv_source(filename)
        CSV.File(filename)
    end

end
