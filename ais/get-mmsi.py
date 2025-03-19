import random
import requests
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor
from pydantic import BaseModel
from typing import Optional


PROXIES = []
THREAD_COUNT = 10
VESSEL_LINKS = []
VESSELS = []
HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36'}

def main():
    

    title = '''

        MIMSI Grabber
        v0.1


    '''

    print(title)

    # load proxies
    load_proxies("proxies_list.txt")

    # get number index page
    
    print("[+] Retrieving list of vessel MMSI's")
    url = "https://www.vesselfinder.com/vessels"
    response = requests.get(url, headers=HEADERS, proxies=get_proxy())

    if response.status_code == 200:
        soup = BeautifulSoup(response.content, 'html.parser')
    else:
        print(f"[!] Exiting: Failed to retrieve index page. Status code: {response.status_code}")


    # to get number of pages, look in the following element:
    # <div class=pagination-controls><span>1 / X</span></div>

    # try to get total number of pages:
    try:
        pagination = soup.find("div", class_="pagination-controls").find("span").text
        page_count = int(pagination.split()[-1].replace(',', ''))
        print(f"[+] Total Pages: {page_count}")
    except:
        print("[!] Exiting: Unable to retrieve total number of pages")
        exit()


    # Retrieve each page and
    page_count = 1
    #page = 1
    #page_links = []
    #while page <= page_count:
    #    url = f"https://www.vesselfinder.com/vessels?page={page}"
    #    page_links.append(url)
    #    page += 1
    page_links = list(map(lambda page: f"https://www.vesselfinder.com/vessels?page={page}", range(1, page_count)))
    print(page_links)

    #a = [1, 2, 3]
    #b = [4, 5, 6]
    #res = map(lambda x, y: x + y, a, b)
    #fahrenheit = map(lambda c: (c * 9/5) + 32, celsius)
    
    # Retrieve Links to Detail pages
    print("[+] Getting links to vessel detail from {page_count} pages")
    with ThreadPoolExecutor(max_workers=THREAD_COUNT) as executor:
        executor.map(get_links, page_links)


    # Retrieve vessel details
    print("[+] Getting details of all vessels")
    with ThreadPoolExecutor(max_workers=THREAD_COUNT) as executor:
        executor.map(get_details, VESSEL_LINKS)


    print(VESSELS)


def get_links(url):
    response = requests.get(url, headers=HEADERS, proxies=get_proxy())
    if response.status_code == 200:
        soup = BeautifulSoup(response.content, 'html.parser')
        pages = soup.find_all("a", class_="ship-link")
        for page in pages:
            VESSEL_LINKS.append(f"https://www.vesselfinder.com{page.get('href')}")
        print(f"[+] Extracted {len(pages)} links from {url}")
    else:
        print("[!] Failed with page {url}")


def get_details(url):
    response = requests.get(url, headers=HEADERS, proxies=get_proxy())
    if response.status_code == 200:
        soup = BeautifulSoup(response.content, 'html.parser')
        
        ship_name = soup.find("h1", class_="title").text # vessel name
        ship_type = soup.find("h2", class_="vst").text.split(',')[0]
        
        trs = soup.find("table", class_="aparams").find_all("tr")
        for tr in trs:
            title = tr.find("td", class_="n3")
            value = tr.din("td", class_="v3")
            
            match title:
                case "IMO / MMSI":
                    ship_mmsi = value.split[-1]
                    ship_imo = value.split[0]
                case "Callsign":
                    ship_callsign = value
                case "Flag":
                    ship_flag = value
                case "Length / Beam":
                    ship_length = f"{value.split[0]}m"
                    ship_beam = f"{value.split[2]}m"
        ship = Vessel(MMSI=ship_mmsi, IMO=ship_imo, name=ship_name, ship_type=ship_type, call_sign=ship_callsign, flag=ship_flag, length=ship_length, beam=ship_beam)
        
        print(f"[+] Ship: {ship}")
        VESSELS.append(ship)
        

    else:
        print("[!] Failed with page {url}")


def load_proxies(path):
    with open(path, 'r') as file:
        for line in file:
            PROXIES.append(line)


def get_proxy():
    proxies = {
         'http': f'http://{random.choice(PROXIES)}',
        'https': f'https://{random.choice(PROXIES)}',
    }
    return proxies


class Vessel(BaseModel):
    MMSI: str
    IMO: str
    name: str
    ship_type: str
    call_sign: str
    flag: str
    length: str
    beam: str

if __name__ == "__main__":
    main()
