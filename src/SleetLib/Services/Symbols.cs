using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection.PortableExecutable;
using System.Text;
using System.Threading.Tasks;
using NuGet.Packaging.Core;
using SleetLib;

namespace Sleet
{
    public class Symbols : ISleetService
    {
        private readonly SleetContext _context;

        public string Name => nameof(Symbols);

        public Symbols(SleetContext context)
        {
            _context = context;
        }

        public async Task AddPackageAsync(PackageInput packageInput)
        {
            var assemblyFiles = packageInput.Zip.Entries
                .Where(e => e.FullName.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                .ToList();

            var pdbFiles = packageInput.Zip.Entries
                .Where(e => e.FullName.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase))
                .ToList();

            foreach (var assembly in assemblyFiles)
            {
                string assemblyHash = null;
                string pdbHash = null;
                ZipArchiveEntry pdbEntry = null;
                var valid = false;

                try
                {
                    using (var stream = await assembly.Open().AsMemoryStreamAsync())
                    using (var reader = new PEReader(stream))
                    {
                        assemblyHash = SymbolsUtility.GetSymbolHashFromAssembly(reader);
                        pdbHash = SymbolsUtility.GetPDBHashFromAssembly(reader);
                    }

                    var assemblyWithoutExt = PathUtility.GetFullPathWithoutExtension(assembly.FullName);

                    pdbEntry = pdbFiles.FirstOrDefault(e => 
                        StringComparer.OrdinalIgnoreCase.Equals(
                            PathUtility.GetFullPathWithoutExtension(e.FullName), assemblyWithoutExt));

                    valid = true;
                }
                catch
                {
                    // Ignore bad assemblies
                }

                if (valid)
                {
                    // Add .dll
                    var fileInfo = new FileInfo(assembly.FullName);
                    var file = GetFile(fileInfo.Name, assemblyHash);

                    await AddFileIfNotExists(assembly, file);

                    // Add .pdb
                    if (pdbEntry != null)
                    {
                        var pdbFileInfo = new FileInfo(pdbEntry.FullName);
                        var pdbFile = GetFile(pdbFileInfo.Name, pdbHash);

                        await AddFileIfNotExists(pdbEntry, pdbFile);
                    }
                }
            }
        }

        public Task RemovePackageAsync(PackageIdentity package)
        {
            return Task.FromResult<bool>(false);
        }

        private async Task AddFileIfNotExists(ZipArchiveEntry entry, ISleetFile file)
        {
            if (await file.Exists(_context.Log, _context.Token) == false)
            {
                using (var stream = await entry.Open().AsMemoryStreamAsync())
                {
                    await file.Write(stream, _context.Log, _context.Token);
                }
            }
        }

        private ISleetFile GetFile(string fileName, string hash)
        {
            var symbolsPath = SymbolsUtility.GetSymbolsServerPath(fileName, hash);

            return _context.Source.Get($"/symbols/{symbolsPath}");
        }
    }
}