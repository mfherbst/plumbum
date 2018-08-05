#!/usr/bin/env python3
# vi: set et ts=4 sw=4 sts=4:

from bs4 import BeautifulSoup
import requests
import argparse
import sys
import re

#TODO generalise to also output stuff to json and so on

def __parse_table(table_tag):
    """
    Parse a single html table characterised by the table_tag object
    into a list of lists of strings
    """
    # TODO: assert table_tag is of the type bs4.element.Tag
    # than make function public

    ret= []
    for row in table_tag.find_all("tr"):
        row_arr=[]
        for col in row.find_all(re.compile("(td|th)")):
            col_text = col.get_text().replace('\n', ' ')
            if (col_text != "" and col_text[0] == '"' and col_text[-1] == '"'):
                col_text = col_text[1:-1]
            row_arr.append(col_text)
        ret.append(row_arr)
    return ret

def extract_all_tables(html_text, limit=None,regex=None):
    """
    Parse html_text and extract all tables
    Returns a list of tables, where each table is 
    a rowwise list of lists of strings

    limit          if provided only the first *limit* tables are parsed
    regex          if not none, only parse html_text after this regex object has been matched
    """

    soup = BeautifulSoup(html_text)
    table_soups=[]
    ret = []

    if (regex is not None):
        start = None
        for tag in soup.find_all(True):
            #if regex.match(tag.get_text()):
            if regex.match(str(tag)):
                start = tag
                break
        if start is None:
            return ret

        table_soups = start.find_all_next("table",limit=limit)
    else:
        table_soups = soup.find_all("table",limit=limit)

    for table_soup in table_soups:
        ret.append(__parse_table(table_soup))
    return ret

def extract_next_table(html_text, regex=None):
    """
    Parse html_text and extract the first table encountered
    Return the table as a list of lists of strings

    regex          if not none, only parse html_text after this regex object has been matched
    """
    ret = extract_all_tables(html_text,regex=regex,limit=1)
    if len(ret) == 0:
        return None
    return ret[0]

def tables_to_csv(tables, quot="", tsep="----",csep="\t"):
    """
    return csv text that is generated from the tables variable

    Each column is separated by csep, each row separatey by newline
    and each table by tsep. Individual fields are quoted with quot.
    """

    csv=""
    
    for table_i in range(len(tables)):
        table = tables[table_i]
        for row_i in range(len(table)):
            row = table[row_i]
            for col_i in range(len(row)):
                col = row[col_i] 

                csv+= (quot + col + quot)
                if (col_i != len(row)-1):
                    csv += csep

            if (row_i != len(table)-1):
                csv+="\n"
        if (table_i != len(tables)-1):
            csv+= (tsep+"\n")

    return csv

if __name__ == "__main__":
    def main():
        parser = argparse.ArgumentParser(description="Parse stdin (or an url) and convert all tables found to a tab-separated list of columns.")
        parser.add_argument("--url", metavar="url", default="-", type=str, help="Url to parse (default: stdin)")
        parser.add_argument("--csep", metavar="csep", default="\t", type=str, help="Column separator character (default: <Tab>)")
        parser.add_argument("--tsep", metavar="tsep", default="----", type=str, help="Table sparation string (default: ----)")
        parser.add_argument("--quot", metavar="quot", default="", type=str, help="Quotation character (default: None)")
        parser.add_argument("--regex", metavar="regex", default=None, type=str, help="Regex to offset into the document: Only tables occurring after the first match of the regex are printed.")
        parser.add_argument("--first", default=False, action='store_true',help="Only convert the first table found")

        args = parser.parse_args()

        text=""
        if args.url == "-":
            text = sys.stdin.read()
            if (text == ""):
                return
        else:
            req = requests.get(args.url)
            if (not req.ok):
                raise SystemExit("Could not download url: " + args.url)
            text = req.text

        rexpr = None
        if (args.regex is not None):
            rexpr = re.compile(args.regex)

        if (args.first):
            tables=extract_all_tables(text,limit=1,regex=rexpr)
        else:
            tables=extract_all_tables(text,regex=rexpr)

        if (len(tables) > 0):
            print (tables_to_csv(tables,quot=args.quot,tsep=args.tsep,csep=args.csep))

main()
