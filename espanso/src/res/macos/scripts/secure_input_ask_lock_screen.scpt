display alert "Expandr couldn't switch off Secure Input automatically. Locking and unlocking your screen usually clears it — try that now?" buttons {"No", "Yes"} default button "Yes"
if button returned of result = "No" then
  return "no"
else
  if button returned of result = "Yes" then
    return "yes"
  end if
end if
