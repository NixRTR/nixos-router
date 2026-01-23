{
  enable = true;  # Master switch - set to false to disable all blocking

  stevenblack = {
    enable = false;
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
    description = "Ads and malware blocking (250K+ domains)";
    updateInterval = "24h";
  };

  phishing-army = {
    enable = true;
    url = "https://phishing.army/download/phishing_army_blocklist.txt";
    description = "Phishing and scam protection";
    updateInterval = "12h";
  };
}
