import requests
from lxml import etree
from io import StringIO
import re
import os

# Function to fetch the new version of a package
def getNewVersion(package_name):
    url = f"https://pub.dev/packages/{package_name}"
    response = requests.get(url)

    # Parse the HTML content
    doc = etree.parse(StringIO(response.text), etree.HTMLParser()).getroot()
    title = doc.xpath('//h1[@class="title"]')[0].text.strip()
    # Extract the version number
    try:
        version = title.split(' ')[1]
        return version
    except IndexError:
        print(f"Could not find version info for {package_name}")
        return None

# Function to extract the list of packages and their current versions from pubspec.yaml
def get_package_list_from_pubspec(pubspec_path):
    with open(pubspec_path, 'r') as file:
        content = file.read()

    # Updated regex to handle versions with + and dot notation
    packages = re.findall(r'(\w+): \^([\d\.\+\-]+)', content)

    return dict(packages)  # Return as a dictionary {package_name: current_version}

# Function to update the versions in pubspec.yaml
def update_pubspec_file(pubspec_path, package_versions):
    # Read the pubspec.yaml file
    with open(pubspec_path, 'r') as file:
        content = file.read()

    # Update each package version in the pubspec file
    for package, new_version in package_versions.items():
        # Updated regex to match the current version, including cases with '+'
        content = re.sub(rf'{package}: \^[\d\.\+\-]+', f'{package}: ^{new_version}', content)

    # Write the updated content back to the file
    with open(pubspec_path, 'w') as file:
        file.write(content)

# Path to the pubspec.yaml file
pubspec_path = os.path.abspath(os.getcwd()) + '/pubspec.yaml'

# Extract the current packages and their versions from pubspec.yaml
current_packages = get_package_list_from_pubspec(pubspec_path)

# Dictionary to store new package versions
package_versions = {}

# Fetch the latest version for each package
for package in current_packages:
    new_version = getNewVersion(package)
    if new_version:
        package_versions[package] = new_version

# Update the pubspec.yaml file
update_pubspec_file(pubspec_path, package_versions)

print("Versions updated in pubspec.yaml")