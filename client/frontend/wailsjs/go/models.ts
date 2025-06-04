export namespace main {
	
	export class Device {
	    deviceID: string;
	    name: string;
	    addresses: string[];
	    compression: string;
	    certName: string;
	    introducer: boolean;
	    skipIntroductionRemovals: boolean;
	    introducedBy: string;
	    paused: boolean;
	    allowedNetworks: string[];
	    autoAcceptFolders: boolean;
	    maxSendKbps: number;
	    maxRecvKbps: number;
	    ignoredFolders: string[];
	    maxRequestKiB: number;
	    untrusted: boolean;
	    remoteGUIPort: number;
	    numConnections: number;
	
	    static createFrom(source: any = {}) {
	        return new Device(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.deviceID = source["deviceID"];
	        this.name = source["name"];
	        this.addresses = source["addresses"];
	        this.compression = source["compression"];
	        this.certName = source["certName"];
	        this.introducer = source["introducer"];
	        this.skipIntroductionRemovals = source["skipIntroductionRemovals"];
	        this.introducedBy = source["introducedBy"];
	        this.paused = source["paused"];
	        this.allowedNetworks = source["allowedNetworks"];
	        this.autoAcceptFolders = source["autoAcceptFolders"];
	        this.maxSendKbps = source["maxSendKbps"];
	        this.maxRecvKbps = source["maxRecvKbps"];
	        this.ignoredFolders = source["ignoredFolders"];
	        this.maxRequestKiB = source["maxRequestKiB"];
	        this.untrusted = source["untrusted"];
	        this.remoteGUIPort = source["remoteGUIPort"];
	        this.numConnections = source["numConnections"];
	    }
	}
	export class Folder {
	    id: string;
	    label: string;
	    path: string;
	
	    static createFrom(source: any = {}) {
	        return new Folder(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.label = source["label"];
	        this.path = source["path"];
	    }
	}

}

