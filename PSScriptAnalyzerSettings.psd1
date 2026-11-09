# PSScriptAnalyzer settings for Clip Creator.
# Run: Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The functions are private GUI helpers inside one script, not exported cmdlets,
        # so -WhatIf/-Confirm support adds nothing here (Set-Progress, Set-RunningState
        # only change the window). Files are only replaced after asking, or as set in
        # "If a clip already exists".
        'PSUseShouldProcessForStateChangingFunctions',
        # Event handlers have fixed (sender, event args) signatures and not every handler
        # uses both.
        'PSReviewUnusedParameter'
    )
}
