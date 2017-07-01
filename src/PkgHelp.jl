module PkgHelp

using PkgDev

function get_sync_dir()
    pkghelp_conf = expanduser("~/.julia/pkghelp.conf")
    sync_dir = if isfile(pkghelp_conf)
        readstring(pkghelp_conf)
    else
        f = ""
        while !isdir(f)
            print("Input Julia pkg sync dir: ")
            f = expanduser(strip(readline(STDIN)))
        end
        open(pkghelp_conf, "w") do file
            write(file, f)
        end
        f
    end
end

function generate(pkg_name, license; kwargs...)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    PkgDev.generate(pkg_name, license; kwargs...)

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(get_sync_dir(), "$(pkg_name).jl")

    println("Moving $(pkg_dir) -> $(pkg_sync_dir)")
    mv(pkg_dir, pkg_sync_dir)

    link(pkg_name)
end

function link(pkg_name)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(get_sync_dir(), "$(pkg_name).jl")

    println("Linking $(pkg_sync_dir) -> $(pkg_dir)")
    symlink(pkg_sync_dir, pkg_dir)
end


end # module
