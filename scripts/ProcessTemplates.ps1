
$mainPath = Split-Path (split-path -parent $MyInvocation.MyCommand.Path) -Parent

$reportTypes = @('Cohorts', 'Workbooks')
$templateExtensions = @('cohort', 'workbook')
$defaultLanguage = 'en-us'
$payload = @{ }
$categoryMetadataFileName = 'categoryResources.json'

# This is the name of where the blob that ALM looks for
$azureBlobFileNameBase = "community-templates-V2";

$docRepos = @(
#    @{ repo="Application-Insights-Workbooks"; lang="en-us"},
    @{ repo="Application-Insights-Workbooks.ru-ru"; lang="ru-ru"}, 
    @{ repo="Application-Insights-Workbooks.cs-cz"; lang="cs-cz"}, 
    @{ repo="Application-Insights-Workbooks.it-it"; lang="it-it"}, 
    @{ repo="Application-Insights-Workbooks.fr-fr"; lang="fr-fr"}, 
    @{ repo="Application-Insights-Workbooks.pl-pl"; lang="pl-pl"}, 
    @{ repo="Application-Insights-Workbooks.zh-tw"; lang="zh-tw"}, 
    @{ repo="Application-Insights-Workbooks.es-es"; lang="es-es"}, 
    @{ repo="Application-Insights-Workbooks.hu-hu"; lang="hu-hu"}, 
    @{ repo="Application-Insights-Workbooks.sv-se"; lang="sv-se"}, 
    @{ repo="Application-Insights-Workbooks.nl-nl"; lang="nl-nl"}, 
    @{ repo="Application-Insights-Workbooks.ja-jp"; lang="ja-jp"}, 
    @{ repo="Application-Insights-Workbooks.tr-tr"; lang="tr-tr"}, 
    @{ repo="Application-Insights-Workbooks.ko-kr"; lang="ko-kr"}, 
    @{ repo="Application-Insights-Workbooks.zh-cn"; lang="zh-cn"}, 
    @{ repo="Application-Insights-Workbooks.pt-br"; lang="pt-br"}
)
$docGitServer = "https://github.com/MicrosoftDocs/"

#----------------------------------------------------------------------------
# GetTemplateContainerData
#----------------------------------------------------------------------------
Function GetTemplateContainerData() {
    param(
        [String] $templateFolderPath,
        [String] $language
    )
    
    $templateMetadata = @{ }

    CopyFromMainIfNotExist $templateFolderPath $language
    $templateFiles = Get-ChildItem $templateFolderPath

    $hasFoundTemplateContent = $false

    foreach ($templateFile in $templateFiles) {

        if ($templateFile.Name -eq 'settings.json') {
            $templateSettings = Get-Content $templateFile.FullName | Out-String | ConvertFrom-Json 

            # Build path of file
            $templateFolderName = Split-Path $templateFolderPath -Leaf
            $templateCategoryFolderPath = Split-Path $templateFolderPath
            $templateCategory = Split-Path $templateCategoryFolderPath -Leaf
            $templateReportTypePath = Split-Path $templateCategoryFolderPath
            $templateReportType = Split-Path $templateReportTypePath -Leaf
    
            $templateMetadata.path = "$templateReportType/$templateCategory/$templateFolderName"
            $templateMetadata.name = $templateSettings.name
            $templateMetadata.author = $templateSettings.author
            $templateMetadata.description = $templateSettings.description
            $templateMetadata.tags = $templateSettings.tags
            $templateMetadata.galleries = $templateSettings.galleries
            $templateMetadata.iconUrl = $templateSettings.icon
            $templateMetadata.readme = $templateSettings.readme
            $templateMetadata.isPreview = $templateSettings.isPreview
        }
        elseif ($templateExtensions.Contains($templateFile.Name.split(".")[-1])) {

            if ($hasFoundTemplateContent) {
                throw "There cannot be more than one content file per template $templateFolderPath"
            }

            $hasFoundTemplateContent = $true

            # This is the template content for default language
            $templateMetadata.Content = Get-Content $templateFile.FullName -Encoding UTF8 | Out-String

        }
    }

    if ( $null -eq $templateMetadata.path -or $null -eq $templateMetadata.Content) {
        throw "Template in folder $templateFolderPath is missing properties"
    }

    return $templateMetadata;
}

#----------------------------------------------------------------------------
# AddCategory
#----------------------------------------------------------------------------
Function AddCategory() {
    param(
        [string] $categoryName,
        [Object] $categories,
        [Object] $categorySettings
    )

    if ($categories.$categoryName) {
        throw "Cannot have duplicate category names ($categoryName)"
    }

    $categories.$categoryName = @{ }

    $categories.$categoryName.ReportName = $reportType
    $categories.$categoryName.CategoryName = $categoryName
    $categories.$categoryName.TemplateContainers = @()

    $categories.$categoryName.SortOrderByLanguage = @{ }
    $categories.$categoryName.NameByLanguage = @{ }
    $categories.$categoryName.DescriptionByLanguage = @{ }

    $categorySettings | Get-Member -type NoteProperty | Foreach-Object {
        $languageProperties = $categorySettings.($_.name)

        $categories.$categoryName.SortOrderByLanguage.($_.name) = $languageProperties.order
        $categories.$categoryName.NameByLanguage.($_.name) = $languageProperties.name
        $categories.$categoryName.DescriptionByLanguage.($_.name) = $languageProperties.description
    }
}

#----------------------------------------------------------------------------
# AddVirtualCategories
#----------------------------------------------------------------------------
Function AddVirtualCategories() {
    param(
        [Object] $categories,
        [string] $categoriesMetadataFilePath
    )

    $virtualCategoriesSettings = Get-Content $categoriesMetadataFilePath | Out-String | ConvertFrom-Json 

    foreach ($virtualCategory in $virtualCategoriesSettings.categories) {

        AddCategory $virtualCategory.key $categories $virtualCategory.settings
    }
}

#----------------------------------------------------------------------------
# AddTemplatesToVirtualGallery
#----------------------------------------------------------------------------
Function AddTemplatesToVirtualGallery() {

    param(
        [Object] $templateMetadata,
        [string] $language
    )

    $virtualGalleries = $templateMetadata.TemplateByLanguage.$language.galleries | Where-Object { ($null -ne $_.categoryKey) -and $payload.$reportType.($_.categoryKey) }

    if ($null -ne $virtualGalleries) {

        # Only keep non-virtual galleries in path category
        $nonVirtualGalleries = $templateMetadata.TemplateByLanguage.$language.galleries | Where-Object { $null -eq $_.categoryKey }
        if ($null -eq $nonVirtualGalleries) {
            $templateMetadata.TemplateByLanguage.$language.galleries = @()
        }
        elseif ($null -eq $nonVirtualGalleries.Count) {
            $templateMetadata.TemplateByLanguage.$language.galleries = @($nonVirtualGalleries)
        }
        else {
            $templateMetadata.TemplateByLanguage.$language.galleries = $nonVirtualGalleries
        }

        # Means there is only one Virtual gallery, so virtual galleries is an object not a list
        if ($null -eq $virtualGalleries.Count) {
            $newTemplateData = (Copy-Object  $templateMetadata)[0]

            $newTemplateData.TemplateByLanguage.$language.galleries = @($virtualGalleries)
            $payload.$reportType.($virtualGalleries.categoryKey).TemplateContainers += $newTemplateData
        }
        else {
            $virtualGalleries | ForEach-Object {

                $newTemplateData = (Copy-Object  $templateMetadata)[0]
                $newTemplateData.TemplateByLanguage.$language.galleries = @($_)
                $payload.$reportType.($_.categoryKey).TemplateContainers += $newTemplateData
            }
        }
    }
}

#----------------------------------------------------------------------------
# Copy-Object
#----------------------------------------------------------------------------
function Copy-Object {
    param($DeepCopyObject)
    $memStream = new-object IO.MemoryStream
    $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
    $formatter.Serialize($memStream, $DeepCopyObject)
    $memStream.Position = 0
    $formatter.Deserialize($memStream)

    return $formatter
}

#----------------------------------------------------------------------------
# CloneLocalizedRepos
#----------------------------------------------------------------------------
Function CloneLocalizedRepos {
    $localSrc = Convert-Path "..\.."

    foreach ($repo in $docRepos) {
        $currentRepo = $repo.repo
        if (Test-Path $localSrc$currentRepo) {
            Write-Host "Trying to clone repo $currentRepo but it already exist on disk, skipping"
        } else {
            Write-Host "Cloning $docGitServer$currentRepo.git at $localSrc$currentRepo"
            git clone $docGitServer$currentRepo".git" $localSrc$currentRepo
        }
    }
}

#----------------------------------------------------------------------------
# CopyFromMainIfNotExist
#----------------------------------------------------------------------------
Function CopyFromMainIfNotExist() {
    param(
        [string] $fullName,
        [string] $language
        )

    $enuPath = $fullName.Replace(".$language\", "\")
    if (!(Test-Path $enuPath)) {
        return
    }
    $enuFiles = Get-ChildItem $enuPath

    foreach($enuFile in $enuFiles) {
        $fileName = $enuFile.Name
        $destinationFile = "$fullName\$fileName"
        if (!(Test-Path $destinationFile)) {
            $fullPath = $enuFile.FullName
            Write-Host "[#WARNING: missing File]: copying file $fullPath to $fullName"
            # copy file from enu to localized folder
            Copy-Item -Path $fullPath -Destination $fullName
            # check and replace "en-us" with the language for any *.json file
            if (Test-Path $destinationFile -PathType leaf -Include "*.json") {
                ((Get-Content -Path $destinationFile -Raw) -replace $defaultLanguage, $language) | Set-Content -Path $destinationFile
            }
        }
    }
}

#----------------------------------------------------------------------------
# BuildingTemplateJson
#----------------------------------------------------------------------------
Function BuildingTemplateJson() {
    param(
        [string] $jsonFileName,
        [string] $language,
        [string] $outputPath
        )

    $currentPath = get-location
    Write-Host ">>>>> Building template json: $jsonFileName in directory $currentPath ..."
    
    $reports = Get-ChildItem $currentPath
    # initialize the payload
    $payload = @{ }

    foreach ($report in $reports) {
        $reportType = $report.Name

        if ($reportTypes.Contains($reportType)) {

            $payload.$reportType = @{ }

            $categories = Get-ChildItem $report.FullName

            #Add virtual categories
            $virtualCategoriesPath = Join-Path $report.FullName $categoryMetadataFileName 
            if ([System.IO.File]::Exists($virtualCategoriesPath)) {

                AddVirtualCategories $payload.$reportType  $virtualCategoriesPath
            }

            foreach ($category in $categories) {

                # Skip if this is the top level categories file (virtual categories), since it was already processed
                if ($category.Name -eq $categoryMetadataFileName) {
                    continue
                }

                $categoryName = $category.Name

                CopyFromMainIfNotExist $category.FullName $language
                $templates = Get-ChildItem $category.FullName

                $categorySettingsPath = Join-Path $category.FullName $categoryMetadataFileName 
                $categorySettings = Get-Content $categorySettingsPath | Out-String | ConvertFrom-Json 

                AddCategory $categoryName ($payload.$reportType) $categorySettings

                foreach ($templateFolder in $templates) {
                    
                    if ($templateFolder -is [System.IO.DirectoryInfo]) {
                        CopyFromMainIfNotExist $templateFolder.FullName $language
                        $templateFiles = Get-ChildItem $templateFolder.FullName
                        $templateMetadata = @{ }
                        $templateMetadata.TemplateByLanguage = @{ }
                        $templateMetadata.Name = $templateFolder.Name

                        # First get template populate template data for default language, which is a top level
                        $templateMetadata.TemplateByLanguage.$language = GetTemplateContainerData $templateFolder.FullName $language

                        AddTemplatesToVirtualGallery $templateMetadata $language

                        #Then look at any subfolders which correspond to localized data
                        foreach ($templateSubfolders in $templateFiles) {

                            if ($templateSubfolders -is [System.IO.DirectoryInfo]) {
                            
                                $templateMetadata.TemplateByLanguage.($templateSubfolders.name) = GetTemplateContainerData $templateSubfolders.FullName $language
                            }
                        }

                        # Add Template container
                        $payload.$reportType.$categoryName.TemplateContainers += $templateMetadata

                    }
                }
            }
        }
    }

    Write-Host "Done building json"

    Write-Host "Copying artifacts"
    $artifactContent = $payload | ConvertTo-Json -depth 10 -Compress

    # create output folder if it doesn't exist
    if (!(Test-Path $outputPath)) {
        mkdir $outputPath
    }

    # delete existing json file
    if (Test-Path "$outputPath\$jsonFileName") {
        Remove-Item "$outputPath\$jsonFileName"
    }

    $artifactContent | Out-File -FilePath "$outputPath\$jsonFileName"
    Write-Host "... DONE building template: $outputPath\$jsonFileName <<<<<"
}

#----------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------
# merge the templates file into a json for each language
#
# community-templates-V2.json:
# Root
#  |- Workbooks (reportFolder)
#        |- Performance (categoryFolder)
#             |- Apdex (templateFolder)
#                 |- en
#                 |   |- settings.json
#                 |   |- readme.md
#                 |   |- Apdex.workbook
#
# community-templates-V2.ko-kr.json:
# Root
#  |- Workbooks (reportFolder)
#        |- Performance (categoryFolder)
#             |- Apdex (templateFolder)
#                 |- ko
#                     |- settings.json
#                     |- readme.md
#                     |- Apdex.workbook        
#----------------------------------------------------------------------------

# pull down all the other localized repos
Write-Host "Get Localized Repos"
CloneLocalizedRepos

# process Enu first
$enuJsonFile = "$azureBlobFileNameBase.json"
$outputPath = Convert-Path "$mainPath\output"
$currentLang = $defaultLanguage
BuildingTemplateJson $enuJsonFile $currentLang $outputPath

# process localized repo
foreach ($locRepo in $docRepos) {
    $currentRepo = $locRepo.repo
    $currentLang = $locRepo.lang
    $currentPath = Convert-Path "$mainPath\..\$currentRepo"
    Set-Location -Path $currentPath
    $jsonFileName = "$azureBlobFileNameBase.$currentLang.json"

    Write-Host ""
    Write-Host "Processing..."
    Write-Host "...Repo: $currentRepo"
    Write-Host "...Language: $currentLang"
    Write-Host "...Directory: $currentPath"
    Write-Host "...OutputFile: $jsonFileName"

    BuildingTemplateJson $jsonFileName $currentLang $outputPath
}

# restore default path
Set-Location -Path $mainPath

Write-Host "Done copying artifacts Existing"
