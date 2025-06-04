export namespace main {
	
	export class Block {
	    hash: string;
	    offset: number;
	    size: number;
	
	    static createFrom(source: any = {}) {
	        return new Block(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.hash = source["hash"];
	        this.offset = source["offset"];
	        this.size = source["size"];
	    }
	}
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
	export class File {
	    name: string;
	    type: string;
	    size: number;
	    modified: string;
	    version: string;
	    localFlags: number;
	    permissions: string;
	    deleted: boolean;
	    invalid: boolean;
	    ignoreDelete: boolean;
	    noPermissions: boolean;
	    sequence: number;
	    modTimeBy: string;
	    blockSize: number;
	    symlinkTarget: string;
	    blocks: Block[];
	
	    static createFrom(source: any = {}) {
	        return new File(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.type = source["type"];
	        this.size = source["size"];
	        this.modified = source["modified"];
	        this.version = source["version"];
	        this.localFlags = source["localFlags"];
	        this.permissions = source["permissions"];
	        this.deleted = source["deleted"];
	        this.invalid = source["invalid"];
	        this.ignoreDelete = source["ignoreDelete"];
	        this.noPermissions = source["noPermissions"];
	        this.sequence = source["sequence"];
	        this.modTimeBy = source["modTimeBy"];
	        this.blockSize = source["blockSize"];
	        this.symlinkTarget = source["symlinkTarget"];
	        this.blocks = this.convertValues(source["blocks"], Block);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
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

