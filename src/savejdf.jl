some_elm(x) = zero(x)
some_elm(::Type{Missing}) = missing
some_elm(::Type{String}) = ""

"""
    save a DataFrames to the outdir
"""
savejdf(outdir, df) =begin
    if VERSION < v"1.3.0-rc1"
        return ssavejdf(outdir, df)
    end

    pmetadatas = Any[missing for i = 1:length(names(df))]

    if !isdir(outdir)
        mkpath(outdir)
    end

    # use a bounded channel to limit
    c1 = Channel{Bool}(Threads.nthreads())
    atexit(()->close(c1))

    for (i, n) in enumerate(names(df))
        put!(c1, true)
        pmetadatas[i] = @spawn begin
            io = BufferedOutputStream(open(joinpath(outdir, string(n)) ,"w"))
            res = compress_then_write(df[!, i], io)
            close(io)
            res
        end
        take!(c1)
    end

    metadatas = fetch.(pmetadatas)

    fnl_metadata = (
        names = names(df),
        rows = size(df, 1),
        metadatas = metadatas,
        version = v"0.2"
    )

    serialize(joinpath(outdir, "metadata.jls"), fnl_metadata)
    fnl_metadata
end

"""
    serially save a DataFrames to the outdir
"""
ssavejdf(outdir, df::DataFrame) = begin
    pmetadatas = Any[missing for i = 1:length(names(df))]

    if !isdir(outdir)
        mkpath(outdir)
    end

    for i = 1:length(names(df))
        io = BufferedOutputStream(open(joinpath(outdir, string(names(df)[i])), "w"))
        pmetadatas[i] = compress_then_write(Array(df[!, i]), io)
        close(io)
    end


    fnl_metadata = (
        names = names(df),
        rows = size(df, 1),
        metadatas = pmetadatas,
        version = v"0.2"
    )

    serialize(joinpath(outdir, "metadata.jls"), fnl_metadata)
    fnl_metadata
end

# figure out from metadata how much space is allocated
get_bytes(metadata) = begin
    if metadata.type == String
        return max(
            metadata.string_compressed_bytes,
            metadata.string_len_bytes,
        )
    elseif metadata.type == Missing
        return 0
    elseif metadata.type >: Missing
        return max(
            get_bytes(metadata.Tmeta),
            get_bytes(metadata.missingmeta),
        )
    else
        return metadata.len
    end
end

hasfieldnames(::Type{T}) where {T} = fieldnames(T) >= 1