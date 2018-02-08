"use strict";
var items = [
{"vibe_elastic_logger.logger.IndexCreator" : "vibe_elastic_logger/logger.IndexCreator.html"},
{"vibe_elastic_logger.logger.ElasticInfo" : "vibe_elastic_logger/logger.ElasticInfo.html"},
{"vibe_elastic_logger.logger.ElasticInfo.hostName" : "vibe_elastic_logger/logger.ElasticInfo.hostName.html"},
{"vibe_elastic_logger.logger.ElasticInfo.portNumber" : "vibe_elastic_logger/logger.ElasticInfo.portNumber.html"},
{"vibe_elastic_logger.logger.ElasticInfo.typeName" : "vibe_elastic_logger/logger.ElasticInfo.typeName.html"},
{"vibe_elastic_logger.logger.ElasticLogger" : "vibe_elastic_logger/logger.ElasticLogger.html"},
{"vibe_elastic_logger.logger.ElasticLogger.this" : "vibe_elastic_logger/logger.ElasticLogger.this.html"},
];
function search(str) {
	var re = new RegExp(str.toLowerCase());
	var ret = {};
	for (var i = 0; i < items.length; i++) {
		var k = Object.keys(items[i])[0];
		if (re.test(k.toLowerCase()))
			ret[k] = items[i][k];
	}
	return ret;
}

function searchSubmit(value, event) {
	console.log("searchSubmit");
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	if (value === "" || event.keyCode == 27) {
		resultTable.style.display = "none";
		return;
	}
	resultTable.style.display = "block";
	var results = search(value);
	var keys = Object.keys(results);
	if (keys.length === 0) {
		var row = resultTable.insertRow();
		var td = document.createElement("td");
		var node = document.createTextNode("No results");
		td.appendChild(node);
		row.appendChild(td);
		return;
	}
	for (var i = 0; i < keys.length; i++) {
		var k = keys[i];
		var v = results[keys[i]];
		var link = document.createElement("a");
		link.href = v;
		link.textContent = k;
		link.attributes.id = "link" + i;
		var row = resultTable.insertRow();
		row.appendChild(link);
	}
}

function hideSearchResults(event) {
	if (event.keyCode != 27)
		return;
	var resultTable = document.getElementById("results");
	while (resultTable.firstChild)
		resultTable.removeChild(resultTable.firstChild);
	resultTable.style.display = "none";
}

