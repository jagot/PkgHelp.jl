module PkgHelp

using PkgDev
using YAML
using Coverage

function expanduser_(path...)
    if is_unix()
        expanduser(joinpath(path...))
    else
        if length(path) > 1 && path[1] == "~"
            joinpath(homedir(), path[2:end]...)
        else
            joinpath(path...)
        end
    end
end

function get_config(fun::Function, variable::String)
    pkghelp_conf = expanduser_("~",".julia","pkghelp.yml")
    config = isfile(pkghelp_conf) ? YAML.load(open(pkghelp_conf)) : Dict()

    if variable in keys(config)
        return config[variable]
    end

    config[variable] = fun()

    open(pkghelp_conf, "w") do file
        for k in keys(config)
            write(file, "$(k): $(config[k])\n")
        end
    end

    config[variable]
end

function get_syncdir()
    get_config("dir") do
        f = ""
        while !isdir(f)
            print("Input Julia pkg sync dir: ")
            path = strip(readline(STDIN))
            path = split(path, contains(path, "/") ? "/" : "\\")
            f = expanduser_(path...)
        end
        f
    end
end

function get_readme()
    get_config("readme") do
        print("Change default README format from Markdown to Org? [Y/n] ")
        lowercase(strip(readline())) == "n" ? "markdown" : "org"
    end
end

function get_git_config(variable)
    try
        strip(readstring(`git config --get $(variable)`))
    catch
        ""
    end
end

function get_github_user()
    github_user = get_git_config("github.user")
    if github_user == ""
        print("Enter your Github username: ")
        github_user = strip(readline(STDIN))
        run(`git config --global github.user $(github_user)`)
    end
    github_user
end

function set_git_ssh(dir)
    cd(dir) do
        git_url = get_git_config("remote.origin.url")
        m = match(r"https://github.com/(.+)/(.+)", git_url)
        if m != nothing
            new_git_url = "git@github.com:$(m[1])/$(m[2])"
            println("Remote url $(git_url) -> $(new_git_url)")
            run(`git remote set-url origin $(new_git_url)`)
            run(`git config remote.origin.pushurl $(new_git_url)`)
        end
    end
end

function org_readme(dir, pkg_name)
    cd(dir) do
        open("README.org", "w") do file
            write(file, "#+TITLE: $(pkg_name).jl\n")
            user_name = get_git_config("user.name")
            user_name != "" && write(file, "#+AUTHOR: $(user_name)\n")
            user_email = get_git_config("user.email")
            user_email != "" && write(file, "#+EMAIL: $(user_email)\n")
            github_user = get_github_user()
            write(file, "\n")
            for (url,badge) in
                [("https://travis-ci.org/$(github_user)/$(pkg_name).jl",
                  "https://travis-ci.org/$(github_user)/$(pkg_name).jl.svg?branch=master"),
                 ("https://coveralls.io/github/$(github_user)/$(pkg_name).jl?branch=master",
                  "https://coveralls.io/repos/github/$(github_user)/$(pkg_name).jl/badge.svg?branch=master"),
                 ("http://codecov.io/gh/$(github_user)/$(pkg_name).jl",
                  "http://codecov.io/gh/$(github_user)/$(pkg_name).jl/branch/master/graph/badge.svg")]
                write(file, "[[$(url)][$(badge)]]\n")
            end
            write(file, "\n")
        end
        rm("README.md")
        run(`git add README.org`)
        run(`git commit -a -m "README.md -> README.org"`)
    end
end

function generate(pkg_name, license; org::Bool=false, kwargs...)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    PkgDev.generate(pkg_name, license; kwargs...)

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(get_syncdir(), "$(pkg_name).jl")

    get_github_user()
    set_git_ssh(pkg_dir)
    get_readme() == "org" && org_readme(pkg_dir, pkg_name)

    if org
        open(joinpath(pkg_dir, "src", "$(pkg_name).org"), "w") do file
            write(file, "#+TITLE: $(pkg_name).jl\n")
            user_name = get_git_config("user.name")
            user_name != "" && write(file, "#+AUTHOR: $(user_name)\n")
            user_email = get_git_config("user.email")
            user_email != "" && write(file, "#+EMAIL: $(user_email)\n")
        end

        open(joinpath(pkg_dir, "src", "$(pkg_name).jl"), "w") do file
            write(file, "module $(pkg_name)\n")
            write(file, "\n")
            write(file, "const codefile = joinpath(dirname(@__FILE__), \"..\", \"deps\", \"build\", \"code.jl\")\n")
            write(file, "if isfile(codefile)\n")
            write(file, "    include(codefile)\n")
            write(file, "else\n")
            write(file, "    error(\"$(pkg_name) not properly installed. Please run Pkg.build(\\\"$(pkg_name)\\\") then restart Julia.\")\n")
            write(file, "end\n")
            write(file, "\n")
            write(file, "end # module\n")
        end

        open(joinpath(pkg_dir, "test", "runtests.jl"), "w") do file
            write(file, "module $(pkg_name)\n")
            write(file, "\n")
            write(file, "const testfile = joinpath(dirname(@__FILE__), \"..\", \"deps\", \"build\", \"tests.jl\")\n")
            write(file, "if isfile(testfile)\n")
            write(file, "    include(testfile)\n")
            write(file, "else\n")
            write(file, "    error(\"$(pkg_name) not properly installed. Please run Pkg.build(\\\"$(pkg_name)\\\") then restart Julia.\")\n")
            write(file, "end\n")
            write(file, "\n")
            write(file, "end # module\n")
        end

        open(joinpath(pkg_dir, "REQUIRE"), "r+") do file
            seekend(file)
            write(file, "\nLiterateOrg\n")
        end

        open(joinpath(pkg_dir, "README.org"), "r+") do file
            seekend(file)
            write(file, "\nThis is a [[https://github.com/jagot/LiterateOrg.jl][LiterateOrg.jl]] project. The documentation is found [[file:src/$(pkg_name).org][within the code]].\n")
        end

        mkpath(joinpath(pkg_dir, "deps"))
        open(joinpath(pkg_dir, "deps", "build.jl"), "w") do file
            write(file, "using LiterateOrg\n")
            write(file, "tangle_package(joinpath(Pkg.dir(\"$(pkg_name)\", \"src\", \"$(pkg_name).org\")), \"$(pkg_name)\")")
        end

        cd(pkg_dir) do
            run(`git add .`)
            run(`git commit -a -m "LiterateOrg project"`)
        end
    end

    println("Moving $(pkg_dir) -> $(pkg_sync_dir)")
    mv(pkg_dir, pkg_sync_dir)

    link(pkg_name)
end

function link(pkg_name)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])

    pkg_dir = Pkg.dir(pkg_name)
    pkg_sync_dir = joinpath(get_syncdir(), "$(pkg_name).jl")

    println("Linking $(pkg_sync_dir) -> $(pkg_dir)")
    symlink(pkg_sync_dir, pkg_dir)
end

function test(pkg_name)
    ismatch(r"\.jl$", pkg_name) && (pkg_name = pkg_name[1:end-3])
    pkg_folder = joinpath(Pkg.dir(pkg_name), "src")
    clean_folder(dirname(pkg_folder))
    Pkg.test(pkg_name, coverage = true)
    coverage = process_folder(pkg_folder)
    coverage_file = joinpath(pkg_folder, "lcov.info")
    LCOV.writefile(coverage_file, coverage)
    try
        real_folder = readlink(dirname(pkg_folder))
        str = readstring(coverage_file)
        open(coverage_file, "w") do file
            write(file, replace(str, dirname(pkg_folder), real_folder))
        end
    catch
    end
    summary = get_summary(coverage)
    @printf("Coverage: %0.2f %%\n", 100summary[1]/summary[2])
end

function clone(github_repo)
    m = match(r"([a-zA-Z0-9]+)/([a-zA-Z0-9]+)$", github_repo)
    user_name = m[1]
    pkg_name = m[2]
    try
        Pkg.installed(pkg_name) != nothing && return
    catch
        Pkg.clone("https://github.com/$(github_repo).jl.git", pkg_name)
    end
    user_name == get_github_user() && set_git_ssh(Pkg.dir(pkg_name))
end

end # module
