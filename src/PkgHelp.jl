module PkgHelp

using PkgDev
using YAML
using Coverage

function get_config()
    pkghelp_conf = expanduser("~/.julia/pkghelp.yml")
    sync_dir = if isfile(pkghelp_conf)
        YAML.load(open(pkghelp_conf))
    else
        f = ""
        while !isdir(f)
            print("Input Julia pkg sync dir: ")
            f = expanduser(strip(readline(STDIN)))
        end
        config = Dict("dir" => f)

        print("Change default README format from Markdown to Org? [Y/n] ")
        config["readme"] = lowercase(strip(readline())) == "n" ? "markdown" : "org"

        open(pkghelp_conf, "w") do file
            for k in keys(config)
                write(file, "$(k): $(config[k])\n")
            end
        end
        config
    end
end

function generate(pkg_name, license; kwargs...)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    PkgDev.generate(pkg_name, license; kwargs...)

    config = get_config()

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(config["dir"], "$(pkg_name).jl")

    println("Moving $(pkg_dir) -> $(pkg_sync_dir)")
    mv(pkg_dir, pkg_sync_dir)

    link(pkg_name)

    cd(pkg_sync_dir) do
        git_url = strip(readstring(`git config --get remote.origin.url`))
        m = match(r"https://github.com/(.+)/(.+)", git_url)
        if m != nothing
            new_git_url = "git@github.com:$(m[1])/$(m[2])"
            println("Remote url $(git_url) -> $(new_git_url)")
            run(`git remote set-url origin $(new_git_url)`)
        end

        if config["readme"] == "org"
            open("README.org", "w") do file
                write(file, "#+TITLE: $(pkg_name).jl\n")
                user_name = strip(readstring(`git config --get user.name`))
                user_name != "" && write(file, "#+AUTHOR: $(user_name)\n")
                user_email = strip(readstring(`git config --get user.email`))
                user_email != "" && write(file, "#+EMAIL: $(user_email)\n")
                write(file, "\n")
                for (url,badge) in
                    [("https://travis-ci.org/jagot/$(pkg_name).jl",
                      "https://travis-ci.org/jagot/$(pkg_name).jl.svg?branch=master"),
                     ("https://coveralls.io/github/jagot/$(pkg_name).jl?branch=master",
                      "https://coveralls.io/repos/jagot/$(pkg_name).jl/badge.svg?branch=master&service=github"),
                     ("http://codecov.io/github/jagot/$(pkg_name).jl?branch=master",
                      "http://codecov.io/github/jagot/$(pkg_name).jl/coverage.svg?branch=master")]
                    write(file, "[[$(url)][$(badge)]]\n")
                end
                write(file, "\n")
            end
            rm("README.md")
            run(`git add README.org`)
            run(`git commit -a -m "README.md -> README.org"`)
        end
    end
end

function link(pkg_name)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    config = get_config()

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(config["dir"], "$(pkg_name).jl")

    println("Linking $(pkg_sync_dir) -> $(pkg_dir)")
    symlink(pkg_sync_dir, pkg_dir)
end

function test(pkg_name)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])
    pkg_folder = joinpath(Pkg.dir(pkg_name), "src")
    files = readdir(pkg_folder)
    filter!(files) do f
        ismatch(r"\.cov$", f)
    end
    map(files) do f
        rm(joinpath(pkg_folder, f))
    end
    Pkg.test(pkg_name, coverage = true)
    summary = get_summary(process_folder(pkg_folder))
    @printf("Coverage: %0.2f %%\n", 100summary[1]/summary[2])
end

end # module
