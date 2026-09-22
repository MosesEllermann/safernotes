# Source releases

The source exporter packages current source files and excludes Git history,
ignored configuration, local databases and build output:

```sh
python3 tools/check_source.py
python3 tools/export_source.py /path/outside/repository/safernotes-source.zip
```

The exporter includes new, non-ignored files and omits deleted files. Review
the working tree before exporting. It refuses symbolic links and known private
file types and token formats. These checks do not prove that every arbitrary
string or binary asset is free of private data.

For a new public repository, unpack the ZIP and initialize a new Git repository
there. Choose the commit author identity you want to publish. Do not copy the
old `.git` directory into that folder. Deleting a file in the current checkout
does not remove its contents from earlier commits in the original repository.

Keep private history backups, signing keys and data backups outside the public
repository. Rotating an exposed credential is still necessary even if its file
has been removed.

Website operator pages are templates. Fill in the appropriate operator details
in the deployment before publishing that website. The source archive contains
no Android signing certificate binding; operators who want HTTPS app links must
provide their own domain association configuration.
